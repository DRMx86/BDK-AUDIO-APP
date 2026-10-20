"""Read only this debug app's Flutter VM URI through a caller-owned JDWP forward.

No method invocation, target suspension, memory mutation, or VM exit commands.
Used when OEM logging prevents Flutter's normal VM-service discovery.
"""
import argparse
import json
from pathlib import Path
import socket
import struct

parser=argparse.ArgumentParser()
parser.add_argument('--port',type=int,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
connection=socket.create_connection(('127.0.0.1',args.port),timeout=5)
connection.settimeout(5)
def read(n):
    data=b''
    while len(data)<n:
        part=connection.recv(n-len(data))
        if not part:raise RuntimeError('Debugger transport closed')
        data+=part
    return data
connection.sendall(b'JDWP-Handshake')
if read(14)!=b'JDWP-Handshake':raise RuntimeError('Unexpected debugger handshake')
next_id=0
def command(group,number,payload=b''):
    global next_id
    next_id+=1
    connection.sendall(struct.pack('>IIBBB',11+len(payload),next_id,0,group,number)+payload)
    while True:
        header=read(11);length,packet,flags=struct.unpack('>IIB',header[:9]);data=read(length-11)
        if not flags&0x80:
            # Acknowledge asynchronous debugger events; never request or suspend.
            connection.sendall(struct.pack('>IIBH',11,packet,0x80,0))
            continue
        if packet!=next_id:continue
        error=struct.unpack('>H',header[9:])[0]
        if error:raise RuntimeError(f'Debugger read error {error}')
        return data
def string(value):
    raw=value.encode();return struct.pack('>I',len(raw))+raw
def get_string(raw,offset):
    length=struct.unpack_from('>I',raw,offset)[0];offset+=4
    return raw[offset:offset+length].decode(),offset+length
try:
    field_size,_,object_size,reference_size,_=struct.unpack('>IIIII',command(1,7))
    classes=command(1,2,string('Lio/flutter/embedding/engine/FlutterJNI;'))
    count=struct.unpack_from('>I',classes)[0]
    if count!=1:raise RuntimeError('Flutter JNI class is not uniquely loaded')
    type_id=classes[5:5+reference_size]
    fields=command(2,4,type_id);total=struct.unpack_from('>I',fields)[0];offset=4;field_id=None
    for _ in range(total):
        fid=fields[offset:offset+field_size];offset+=field_size
        name,offset=get_string(fields,offset);signature,offset=get_string(fields,offset);offset+=4
        if name in ('vmServiceUri','observatoryUri') and signature=='Ljava/lang/String;':field_id=fid
    if field_id is None:raise RuntimeError('Flutter service URI field is unavailable')
    value=command(2,6,type_id+struct.pack('>I',1)+field_id)
    if value[4]!=ord('s'):raise RuntimeError('Flutter URI is not a string')
    object_id=value[5:5+object_size]
    if int.from_bytes(object_id,'big')==0:raise RuntimeError('Flutter VM service has no URI')
    uri,_=get_string(command(10,1,object_id),0)
    if not uri.startswith('http://127.0.0.1:'):raise RuntimeError('Unexpected Flutter service address')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps({'uri':uri}),encoding='utf-8')
    print('Read the debug app Flutter VM URI; token saved privately in ignored artifacts.')
finally:
    try:command(1,6)  # Dispose debugger connection; do NOT terminate the VM.
    finally:connection.close()
