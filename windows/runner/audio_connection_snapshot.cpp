#include "audio_connection_snapshot.h"
#include <Windows.h>
#include <initguid.h>
#include <devguid.h>
#include <devpkey.h>
#include <mmdeviceapi.h>
#include <propkey.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propvarutil.h>
#include <setupapi.h>
#include <bthsdpdef.h>
#include <bluetoothapis.h>
#include <wrl/client.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cwctype>
#include <vector>
namespace bdk_audio {
namespace {
using Microsoft::WRL::ComPtr;
constexpr size_t kMaximumItems = 256;
constexpr DWORD kMaximumPropertyBytes = 8192;
const DEVPROPKEY kBluetoothAddress = {PKEY_DeviceInterface_Bluetooth_DeviceAddress.fmtid, PKEY_DeviceInterface_Bluetooth_DeviceAddress.pid};
const DEVPROPKEY kBluetoothService = {PKEY_DeviceInterface_Bluetooth_ServiceGuid.fmtid, PKEY_DeviceInterface_Bluetooth_ServiceGuid.pid};
const GUID kAudioSinkService = {0x0000110b, 0, 0x1000, {0x80,0,0,0x80,0x5f,0x9b,0x34,0xfb}};
const GUID kAudioSourceService = {0x0000110a, 0, 0x1000, {0x80,0,0,0x80,0x5f,0x9b,0x34,0xfb}};
const GUID kHandsFreeService = {0x0000111e, 0, 0x1000, {0x80,0,0,0x80,0x5f,0x9b,0x34,0xfb}};
const GUID kHandsFreeGateway = {0x0000111f, 0, 0x1000, {0x80,0,0,0x80,0x5f,0x9b,0x34,0xfb}};
std::string Utf8(const std::wstring& text) {
  if (text.empty() || text.size() > 4096) return {};
  const int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (count <= 0 || count > 8192) return {};
  std::string result(static_cast<size_t>(count), 0);
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), count, nullptr, nullptr);
  return result;
}
std::string GuidString(const GUID& guid) {
  if (IsEqualGUID(guid, GUID_NULL)) return {};
  wchar_t value[40]{}; StringFromGUID2(guid, value, 40); return Utf8(value);
}
class Apartment {
 public:
  Apartment() : result(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}
  ~Apartment() { if (SUCCEEDED(result)) CoUninitialize(); }
  HRESULT result;
};
struct Variant {
  Variant() { PropVariantInit(&value); }
  ~Variant() { PropVariantClear(&value); }
  PROPVARIANT value;
};
std::string EndpointContainer(IPropertyStore* properties) {
  Variant property;
  if (FAILED(properties->GetValue(PKEY_Device_ContainerId, &property.value)) || property.value.vt != VT_CLSID || !property.value.puuid) return {};
  return GuidString(*property.value.puuid);
}
std::string EndpointName(IPropertyStore* properties) {
  Variant property;
  if (FAILED(properties->GetValue(PKEY_Device_FriendlyName, &property.value)) || property.value.vt != VT_LPWSTR || !property.value.pwszVal) return {};
  return Utf8(property.value.pwszVal);
}
class DeviceSet {
 public:
  DeviceSet() : value(SetupDiGetClassDevsW(&GUID_DEVCLASS_MEDIA, nullptr, nullptr, DIGCF_PRESENT)) {}
  ~DeviceSet() { if (value != INVALID_HANDLE_VALUE) SetupDiDestroyDeviceInfoList(value); }
  HDEVINFO value;
};
std::vector<BYTE> Property(HDEVINFO set, SP_DEVINFO_DATA* device, const DEVPROPKEY& key, DEVPROPTYPE expected) {
  DWORD size = 0; DEVPROPTYPE type = 0;
  SetupDiGetDevicePropertyW(set, device, &key, &type, nullptr, 0, &size, 0);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || size == 0 || size > kMaximumPropertyBytes || type != expected) return {};
  std::vector<BYTE> bytes(size);
  if (!SetupDiGetDevicePropertyW(set, device, &key, &type, bytes.data(), size, &size, 0) || type != expected) return {};
  return bytes;
}
std::wstring DeviceString(HDEVINFO set, SP_DEVINFO_DATA* device, const DEVPROPKEY& key) {
  const auto bytes = Property(set, device, key, DEVPROP_TYPE_STRING);
  if (bytes.size() < sizeof(wchar_t) || bytes.size() % sizeof(wchar_t) != 0) return {};
  const auto* text = reinterpret_cast<const wchar_t*>(bytes.data());
  const size_t length = bytes.size() / sizeof(wchar_t);
  if (text[length - 1] != 0) return {};
  return std::wstring(text, wcsnlen_s(text, length));
}
std::optional<GUID> DeviceGuid(HDEVINFO set, SP_DEVINFO_DATA* device, const DEVPROPKEY& key) {
  const auto bytes = Property(set, device, key, DEVPROP_TYPE_GUID);
  if (bytes.size() != sizeof(GUID)) return std::nullopt;
  GUID result{}; memcpy(&result, bytes.data(), sizeof(result)); return result;
}
bool IsBluetoothEnumerator(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towupper(c)); });
  return value.rfind(L"BTH", 0) == 0;
}
}  // namespace
AudioSnapshotReport ReadWindowsAudioSnapshot() {
  Apartment apartment;
  AudioEvidence evidence;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
  const auto incomplete = [&]() { evidence.enumeration_complete = false; return ReduceAudioEvidence(evidence); };
  if (FAILED(apartment.result)) return incomplete();
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) return incomplete();
  ComPtr<IMMDeviceCollection> endpoints;
  if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &endpoints))) return incomplete();
  UINT count = 0;
  if (FAILED(endpoints->GetCount(&count)) || count > kMaximumItems) return incomplete();
  for (UINT i = 0; i < count; ++i) {
    if (std::chrono::steady_clock::now() > deadline) return incomplete();
    ComPtr<IMMDevice> device; ComPtr<IPropertyStore> properties; DWORD state = 0;
    if (FAILED(endpoints->Item(i, &device)) || FAILED(device->GetState(&state)) || FAILED(device->OpenPropertyStore(STGM_READ, &properties))) return incomplete();
    evidence.endpoints.push_back({EndpointContainer(properties.Get()), EndpointName(properties.Get()), true, (state & DEVICE_STATE_ACTIVE) != 0});
  }
  DeviceSet adapters;
  if (adapters.value == INVALID_HANDLE_VALUE) return incomplete();
  for (DWORD i = 0;; ++i) {
    if (std::chrono::steady_clock::now() > deadline || i >= kMaximumItems) return incomplete();
    SP_DEVINFO_DATA device{}; device.cbSize = sizeof(device);
    if (!SetupDiEnumDeviceInfo(adapters.value, i, &device)) {
      if (GetLastError() != ERROR_NO_MORE_ITEMS) return incomplete();
      break;
    }
    const auto container = DeviceGuid(adapters.value, &device, DEVPKEY_Device_ContainerId);
    const auto service = DeviceGuid(adapters.value, &device, kBluetoothService);
    const auto source = DeviceString(adapters.value, &device, DEVPKEY_Device_EnumeratorName);
    BluetoothAudioProfile profile = IsBluetoothEnumerator(source) ? BluetoothAudioProfile::kUnknownBluetooth : BluetoothAudioProfile::kNotBluetooth;
    if (service) {
      if (IsEqualGUID(*service, kAudioSinkService)) profile = BluetoothAudioProfile::kA2dpSink;
      else if (IsEqualGUID(*service, kAudioSourceService)) profile = BluetoothAudioProfile::kA2dpSource;
      else if (IsEqualGUID(*service, kHandsFreeService) || IsEqualGUID(*service, kHandsFreeGateway)) profile = BluetoothAudioProfile::kHandsFree;
    }
    evidence.adapters.push_back({container ? GuidString(*container) : "", Utf8(DeviceString(adapters.value, &device, kBluetoothAddress)), profile, true});
  }
  BLUETOOTH_DEVICE_SEARCH_PARAMS search{};
  search.dwSize = sizeof(search); search.fReturnConnected = TRUE; search.fIssueInquiry = FALSE;
  BLUETOOTH_DEVICE_INFO info{}; info.dwSize = sizeof(info);
  HBLUETOOTH_DEVICE_FIND found = BluetoothFindFirstDevice(&search, &info);
  if (!found) {
    const DWORD error = GetLastError();
    if (error != ERROR_NO_MORE_ITEMS && error != ERROR_SUCCESS && error != ERROR_NOT_FOUND) return incomplete();
  } else {
    bool complete = true;
    do {
      if (std::chrono::steady_clock::now() > deadline || evidence.bluetooth.size() >= kMaximumItems) { complete = false; break; }
      char address[18]{};
      const auto raw = info.Address.ullLong;
      std::snprintf(address, sizeof(address), "%02x:%02x:%02x:%02x:%02x:%02x", static_cast<unsigned>((raw >> 40) & 255), static_cast<unsigned>((raw >> 32) & 255), static_cast<unsigned>((raw >> 24) & 255), static_cast<unsigned>((raw >> 16) & 255), static_cast<unsigned>((raw >> 8) & 255), static_cast<unsigned>(raw & 255));
      evidence.bluetooth.push_back({address, Utf8(info.szName), info.fConnected != FALSE});
      info.dwSize = sizeof(info);
    } while (BluetoothFindNextDevice(found, &info));
    if (complete && GetLastError() != ERROR_NO_MORE_ITEMS) complete = false;
    BluetoothFindDeviceClose(found);
    if (!complete) return incomplete();
  }
  return ReduceAudioEvidence(evidence);
}
}  // namespace bdk_audio
