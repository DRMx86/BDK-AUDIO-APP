"""Behavior tests against the real native renderer C ABI, without BLE or mocks."""
import ctypes as c
import math
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DLL = ROOT / "build/native_renderer/Release/bdk_led_engine.dll"
FRAME_BYTES = 16 * 16 * 4
CORE_WIDTH = 256
HALO_WIDTH = 128
CORE_FLOATS = CORE_WIDTH * CORE_WIDTH * 4
HALO_FLOATS = HALO_WIDTH * HALO_WIDTH * 4


class RendererTests(unittest.TestCase):
    def setUp(self):
        path = Path(os.environ.get("BDK_LED_LIBRARY", str(DEFAULT_DLL)))
        self.assertTrue(path.is_file(), "Native firmware effect engine has not been built")
        self.lib = c.CDLL(str(path))
        self.lib.bdk_led_create.restype = c.c_void_p
        self.lib.bdk_led_destroy.argtypes = [c.c_void_p]
        self.lib.bdk_led_select.argtypes = [c.c_void_p, c.c_int]
        self.lib.bdk_led_settings.argtypes = [c.c_void_p, c.POINTER(c.c_uint8), c.c_int]
        self.lib.bdk_led_render.argtypes = [c.c_void_p, c.POINTER(c.c_float), c.c_uint8,
                                          c.c_int, c.POINTER(c.c_uint8), c.c_int]
        self.lib.bdk_led_name.argtypes = [c.c_int]
        self.lib.bdk_led_name.restype = c.c_char_p
        self.ctx = self.lib.bdk_led_create()
        self.assertTrue(self.ctx)
        self.audio = (c.c_float * 7)(.7, .4, .2, -18, -24, -30, .7)
        self.out = (c.c_uint8 * FRAME_BYTES)()
        self.addCleanup(self.lib.bdk_led_destroy, self.ctx)

    def settings(self, effect, brightness=100, gradient=0, context=None):
        values = (c.c_uint8 * 10)(effect, brightness, 50, 255, 128, 0, 0, 128, 255, gradient)
        self.assertEqual(self.lib.bdk_led_settings(
            self.ctx if context is None else context, values, 10), 1)

    def render(self, flags=2, demo=False, context=None):
        pointer = self.ctx if context is None else context
        written = self.lib.bdk_led_render(pointer, self.audio, flags, int(demo),
                                          self.out, FRAME_BYTES)
        self.assertEqual(written, FRAME_BYTES)
        return bytes(self.out)

    def fresh_context(self):
        context = self.lib.bdk_led_create()
        self.assertTrue(context)
        self.addCleanup(self.lib.bdk_led_destroy, context)
        return context

    def light_fields_function(self):
        self.assertTrue(hasattr(self.lib, "bdk_led_light_fields"),
                        "Native separable Gaussian field export is missing")
        function = self.lib.bdk_led_light_fields
        function.argtypes = [c.c_void_p, c.POINTER(c.c_uint8), c.c_int, c.c_float,
                             c.POINTER(c.c_float), c.c_int,
                             c.POINTER(c.c_float), c.c_int]
        function.restype = c.c_int
        return function

    def light_fields(self, source, sigma=1.7, context=None):
        function = self.light_fields_function()
        rgba = (c.c_uint8 * FRAME_BYTES).from_buffer_copy(source)
        core = (c.c_float * CORE_FLOATS)()
        halo = (c.c_float * HALO_FLOATS)()
        pointer = self.ctx if context is None else context
        self.assertEqual(function(pointer, rgba, FRAME_BYTES, sigma,
                                  core, CORE_FLOATS, halo, HALO_FLOATS), 1)
        return core, halo

    def test_beat_pulse_flashes_uniform_panel_with_firmware_color(self):
        self.settings(1)
        frame = self.render(flags=3)
        pixels = [frame[i:i+4] for i in range(0, len(frame), 4)]
        self.assertEqual(set(pixels), {bytes([254, 195, 21, 255])})

    def test_beat_pulse_decays_between_beats(self):
        self.settings(1)
        first = self.render(flags=3)
        last = first
        for _ in range(12):
            last = self.render()
        self.assertLess(sum(last[:3]), sum(first[:3]))

    def test_bass_reactor_retains_circular_symmetry(self):
        self.settings(14)
        for _ in range(12):
            frame = self.render()
        def pixel(x, y):
            i = (y * 16 + x) * 4
            return frame[i:i+4]
        self.assertTrue(any(frame[i] for i in range(0, FRAME_BYTES, 4)))
        for y in range(16):
            for x in range(16):
                self.assertEqual(pixel(x, y), pixel(15-y, x), (x, y))

    def test_zero_brightness_is_black_for_every_effect(self):
        for effect in range(22):
            with self.subTest(effect=effect):
                self.settings(effect, 0)
                frame = self.render(flags=3)
                self.assertEqual(set(frame[i:i+4] for i in range(0, FRAME_BYTES, 4)),
                                 {bytes([0, 0, 0, 255])})

    def test_invalid_effect_does_not_replace_active_effect(self):
        self.settings(1)
        self.assertEqual(self.lib.bdk_led_select(self.ctx, 255), 0)
        frame = self.render(flags=3)
        self.assertEqual(len(set(frame[i:i+4] for i in range(0, FRAME_BYTES, 4))), 1)

    def test_reselecting_same_effect_does_not_reset_pulse(self):
        self.settings(1)
        first = self.render(flags=3)
        self.assertEqual(self.lib.bdk_led_select(self.ctx, 1), 1)
        second = self.render()
        self.assertLess(sum(second[:3]), sum(first[:3]))

    def test_short_output_is_rejected_without_writing(self):
        sentinel = (c.c_uint8 * 8)(*([123] * 8))
        self.assertEqual(self.lib.bdk_led_render(self.ctx, self.audio, 2, 0, sentinel, 8), 0)
        self.assertEqual(bytes(sentinel), bytes([123] * 8))

    def test_invalid_settings_are_rejected(self):
        values = (c.c_uint8 * 10)(21, 101, 50, 255, 128, 0, 0, 128, 255, 0)
        self.assertEqual(self.lib.bdk_led_settings(self.ctx, values, 10), 0)
        values[1] = 100
        values[9] = 5
        self.assertEqual(self.lib.bdk_led_settings(self.ctx, values, 10), 0)

    def test_all_22_effects_render_live_and_demo_frames(self):
        names = set()
        for effect in range(22):
            with self.subTest(effect=effect):
                names.add(self.lib.bdk_led_name(effect))
                self.settings(effect)
                nonzero = False
                for i in range(45):
                    frame = self.render(flags=3 if i % 15 == 0 else 2)
                    nonzero |= any(frame[j] for j in range(0, FRAME_BYTES, 4))
                    self.assertEqual(set(frame[3::4]), {255})
                self.assertTrue(nonzero)
                self.assertEqual(len(self.render(demo=True)), FRAME_BYTES)
        self.assertEqual(len(names), 22)

    def test_particle_burst_cold_demo_keeps_animating_after_center_glow_settles(self):
        self.settings(11, 70)
        frames = [self.render(demo=True) for _ in range(120)]
        # A changing startup glow alone does not establish a particle burst.
        self.assertGreater(len(set(frames[60:])), 1)
        self.assertTrue(any(sum(any(frame[i:i+3]) for i in range(0, FRAME_BYTES, 4)) > 9
                            for frame in frames))

    def test_meteor_shower_cold_demo_spawns_visible_moving_meteors(self):
        self.settings(15, 70)
        frames = [self.render(demo=True) for _ in range(120)]
        self.assertTrue(any(any(frame[0::4] + frame[1::4] + frame[2::4])
                            for frame in frames))
        self.assertGreater(len(set(frames[60:])), 1)

    def test_particle_demo_reapplying_settings_does_not_restart_beat_cycle(self):
        frames = []
        for _ in range(45):
            self.settings(11, 70)
            frames.append(self.render(demo=True))
        self.assertTrue(any(sum(any(frame[i:i+3]) for i in range(0, FRAME_BYTES, 4)) > 9
                            for frame in frames))

    def test_idle_spectrum_demo_does_not_repeat_short_animation_loops(self):
        self.settings(0)
        frames = [self.render(demo=True) for _ in range(1536)]
        # After settling, a visible idle sequence should not replay the same
        # short loop every 2-17 seconds. Movement alone already passed before
        # this change and does not establish randomized idle behavior.
        for lag in (64, 128, 256, 512):
            with self.subTest(lag_frames=lag):
                changed = sum(frames[i] != frames[i + lag]
                              for i in range(512, 768))
                self.assertGreater(changed, 192)

    def test_spectrum_demo_progression_belongs_to_each_context(self):
        other = self.fresh_context()
        self.settings(0)
        self.settings(0, context=other)
        for frame in range(360):
            with self.subTest(frame=frame):
                self.assertEqual(self.render(demo=True),
                                 self.render(demo=True, context=other))

    def test_spectrum_demo_same_effect_brightness_configuration_keeps_progress(self):
        other = self.fresh_context()
        self.settings(0)
        self.settings(0, context=other)
        for frame in range(360):
            # UI configuration can run each frame. Even a temporary brightness
            # edit must not restart the idle sequence when the effect is kept.
            self.settings(0, 37, context=other)
            self.settings(0, 100, context=other)
            with self.subTest(frame=frame):
                self.assertEqual(self.render(demo=True),
                                 self.render(demo=True, context=other))

    def test_spectrum_live_frames_stay_identical_while_other_context_runs_idle(self):
        live_reference = self.fresh_context()
        idle = self.fresh_context()
        self.settings(0)
        self.settings(0, context=live_reference)
        self.settings(0, context=idle)
        levels = ((0, 0, 0), (.03, .18, .01), (.7, .4, .2),
                  (1, .01, .5), (.02, .02, .02), (0, 0, 0))
        for frame in range(360):
            bass, mid, high = levels[(frame // 15) % len(levels)]
            self.audio = (c.c_float * 7)(bass, mid, high, -18, -24, -30, .7)
            self.render(demo=True, context=idle)
            with self.subTest(frame=frame):
                flags = 3 if frame % 30 == 0 else 2
                self.assertEqual(self.render(flags=flags),
                                 self.render(flags=flags, context=live_reference))

    def test_spectrum_zero_live_input_is_black_instead_of_starting_idle_demo(self):
        self.settings(0)
        self.audio = (c.c_float * 7)(0, 0, 0, -120, -120, -120, 0)
        for _ in range(90):
            frame = self.render(flags=2, demo=False)
            self.assertEqual(set(frame[i:i+4] for i in range(0, FRAME_BYTES, 4)),
                             {bytes([0, 0, 0, 255])})

    def test_spectrum_idle_demo_keeps_zero_brightness_black(self):
        self.settings(0, 0)
        for _ in range(180):
            frame = self.render(demo=True)
            self.assertEqual(set(frame[i:i+4] for i in range(0, FRAME_BYTES, 4)),
                             {bytes([0, 0, 0, 255])})

    def test_light_fields_match_independent_double_gaussian_and_premultiplied_alpha(self):
        source = bytearray(FRAME_BYTES)
        for x, y, rgba in ((2, 4, (255, 70, 10, 255)),
                           (11, 9, (20, 210, 180, 128)),
                           (7, 14, (120, 55, 235, 64))):
            source[(y * 16 + x) * 4:(y * 16 + x) * 4 + 4] = bytes(rgba)
        core, halo = self.light_fields(source)
        for field, width, minimum, span, sigma in (
                (core, 256, -4.0, 24.0, .8),
                (halo, 128, 0.0, 16.0, 1.7)):
            peak_nodes = ((69, 90), (165, 143)) if width == 256 else ((20, 36), (91, 75))
            for x, y in ((0, 0), (width - 1, width - 1),
                         (width // 3, width // 4),
                         (width // 2, width // 2),
                         (width * 3 // 4, width * 2 // 3), *peak_nodes):
                with self.subTest(width=width, x=x, y=y):
                    # The output grid includes BOTH domain endpoints. LED
                    # samples remain at half-cell centers independently.
                    position = (minimum + x * span / (width - 1),
                                minimum + y * span / (width - 1))
                    expected = gaussian_reference(source, *position, sigma)
                    actual = field_pixel(field, width, x, y)
                    for channel in range(3):
                        self.assertAlmostEqual(actual[channel], expected[channel],
                                               delta=2e-6)
                    self.assertEqual(actual[3], 1)

    def test_light_fields_half_split_stays_continuous_at_the_boundary(self):
        source = bytearray(FRAME_BYTES)
        for y in range(16):
            for x in range(16):
                source[(y * 16 + x) * 4:(y * 16 + x) * 4 + 4] = bytes(
                    (255, 0, 0, 255) if x < 8 else (0, 0, 255, 255))
        core, halo = self.light_fields(source)
        for field, width, minimum, span, sigma in (
                (core, 256, -4.0, 24.0, .8),
                (halo, 128, 0.0, 16.0, 1.7)):
            y = width // 2
            for x in (width // 2 - 2, width // 2 - 1,
                      width // 2, width // 2 + 1):
                expected = gaussian_reference(
                    source, minimum + x * span / (width - 1),
                    minimum + y * span / (width - 1), sigma)
                actual = field_pixel(field, width, x, y)
                for channel in (0, 2):
                    self.assertAlmostEqual(actual[channel], expected[channel], delta=2e-6)
            left = field_pixel(field, width, width // 2 - 1, y)
            right = field_pixel(field, width, width // 2, y)
            self.assertGreater(left[0], right[0])
            self.assertLess(left[2], right[2])
            self.assertAlmostEqual(left[0], right[2], delta=2e-6)
            self.assertAlmostEqual(left[2], right[0], delta=2e-6)

    def test_light_fields_are_symmetric_horizontally_and_vertically(self):
        source = bytearray(FRAME_BYTES)
        for x, y in ((5, 6), (10, 6), (5, 9), (10, 9)):
            source[(y * 16 + x) * 4:(y * 16 + x) * 4 + 4] = bytes((220, 90, 30, 255))
        core, halo = self.light_fields(source, sigma=1.25)
        for field, width in ((core, 256), (halo, 128)):
            for x, y in ((0, 0), (width // 4, width // 3),
                         (width // 2 - 1, width * 3 // 4)):
                value = field_pixel(field, width, x, y)
                horizontal = field_pixel(field, width, width - 1 - x, y)
                vertical = field_pixel(field, width, x, width - 1 - y)
                for channel in range(4):
                    self.assertAlmostEqual(value[channel], horizontal[channel], delta=2e-6)
                    self.assertAlmostEqual(value[channel], vertical[channel], delta=2e-6)

    def test_light_fields_invalid_arguments_leave_both_outputs_untouched(self):
        function = self.light_fields_function()
        rgba = (c.c_uint8 * FRAME_BYTES)()
        core = (c.c_float * CORE_FLOATS)()
        halo = (c.c_float * HALO_FLOATS)()
        c.memset(core, 0xA5, c.sizeof(core))
        c.memset(halo, 0x5A, c.sizeof(halo))
        original_core, original_halo = bytes(core), bytes(halo)
        arguments = [self.ctx, rgba, FRAME_BYTES, 1.7,
                     core, CORE_FLOATS, halo, HALO_FLOATS]
        for index, invalid in ((0, None), (1, None), (2, 1023), (2, 1025),
                               (3, float('nan')), (3, float('inf')),
                               (3, .249), (3, 32.01), (4, None),
                               (5, CORE_FLOATS - 1), (5, -1),
                               (6, None), (7, HALO_FLOATS - 1), (7, -1)):
            with self.subTest(argument=index, value=invalid):
                invalid_arguments = list(arguments)
                invalid_arguments[index] = invalid
                self.assertEqual(function(*invalid_arguments), 0)
                self.assertEqual(bytes(core), original_core)
                self.assertEqual(bytes(halo), original_halo)

    def test_light_fields_black_source_is_exactly_black_with_opaque_output(self):
        source = bytes((0, 0, 0, 255)) * 256
        for sigma in (.25, 32.0):
            for field in self.light_fields(source, sigma=sigma):
                self.assertEqual(set(field[0::4]), {0.0})
                self.assertEqual(set(field[1::4]), {0.0})
                self.assertEqual(set(field[2::4]), {0.0})
                self.assertEqual(set(field[3::4]), {1.0})

    def test_light_fields_sigma_changes_preserve_core_and_rebuild_halo(self):
        source = bytearray(FRAME_BYTES)
        source[(8 * 16 + 8) * 4:(8 * 16 + 8) * 4 + 4] = bytes((255, 40, 5, 255))
        first_core, first_halo = self.light_fields(source, sigma=.75)
        second_core, second_halo = self.light_fields(source, sigma=2.5)
        again_core, again_halo = self.light_fields(source, sigma=.75)
        self.assertEqual(bytes(first_core), bytes(second_core))
        self.assertEqual(bytes(first_core), bytes(again_core))
        self.assertNotEqual(bytes(first_halo), bytes(second_halo))
        self.assertEqual(bytes(first_halo), bytes(again_halo))

    def test_light_fields_calls_do_not_advance_spectrum_live_or_idle_sequence(self):
        source = bytearray(FRAME_BYTES)
        source[(7 * 16 + 3) * 4:(7 * 16 + 3) * 4 + 4] = bytes((255, 180, 20, 255))
        for demo in (False, True):
            reference, candidate = self.fresh_context(), self.fresh_context()
            self.settings(0, 70, context=reference)
            self.settings(0, 70, context=candidate)
            for frame in range(12):
                self.light_fields(source, sigma=.75 if frame % 2 else 2.5,
                                  context=candidate)
                with self.subTest(demo=demo, frame=frame):
                    self.assertEqual(self.render(demo=demo, context=reference),
                                     self.render(demo=demo, context=candidate))


def field_pixel(field, width, x, y):
    offset = (y * width + x) * 4
    return tuple(field[offset:offset + 4])


def gaussian_reference(source, position_x, position_y, sigma):
    """Independent double-precision 2D sum; no separable/cache implementation."""
    result = [0.0, 0.0, 0.0]
    for y in range(16):
        for x in range(16):
            offset = (y * 16 + x) * 4
            distance_squared = ((position_x - x - .5) ** 2 +
                                (position_y - y - .5) ** 2)
            weight = math.exp(-distance_squared / (2 * sigma * sigma)) / (
                2 * math.pi * sigma * sigma)
            alpha = source[offset + 3] / 255.0
            for channel in range(3):
                result[channel] += source[offset + channel] / 255.0 * alpha * weight
    return result


if __name__ == "__main__":
    unittest.main(verbosity=2)
