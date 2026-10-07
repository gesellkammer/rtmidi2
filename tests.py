#!/usr/bin/env python

import time
import unittest

import rtmidi2 as rtmidi

class RtMidiTestCase(unittest.TestCase):

    NOTE_ON = [0x90, 48, 100]
    NOTE_OFF = [0x80, 48, 16]
    TEST_PORT_NAME = 'rtmidi test port'
    DELAY = 0.1

    def setUp(self):
        self.midi_out = rtmidi.MidiOut()
        self.midi_out.open_virtual_port(self.TEST_PORT_NAME)

        self.midi_in = rtmidi.MidiIn()
        # ALSA exposes virtual ports as "CLIENT:name N:M"; macOS uses the
        # bare name. Match either via glob.
        time.sleep(0.2)
        try:
            self.midi_in.open_port(self.TEST_PORT_NAME)
        except ValueError:
            self.midi_in.open_port("*%s*" % self.TEST_PORT_NAME)

    def tearDown(self):
        self.midi_in.close_port()
        self.midi_in = None
        self.midi_out.close_port()
        self.midi_out = None

    def test_send_and_get_message(self):
        self.midi_out.send_message(self.NOTE_ON)
        self.midi_out.send_message(self.NOTE_OFF)
        time.sleep(self.DELAY)
        incoming_message_1 = self.midi_in.get_message()
        incoming_message_2 = self.midi_in.get_message()
        self.assertEqual(incoming_message_1, self.NOTE_ON)
        self.assertEqual(incoming_message_2, self.NOTE_OFF)

    def test_callback(self):
        incoming_messages = []
        def callback(message, time_stamp):
            incoming_messages.append(message)
        self.midi_in.callback = callback
        self.midi_out.send_message(self.NOTE_ON)
        self.midi_out.send_message(self.NOTE_OFF)
        time.sleep(self.DELAY)
        self.assertEqual(incoming_messages, [self.NOTE_ON, self.NOTE_OFF])

        incoming_messages = []
        self.midi_in.callback = None
        self.midi_out.send_message(self.NOTE_ON)
        self.midi_out.send_message(self.NOTE_OFF)
        time.sleep(self.DELAY)
        self.assertEqual(incoming_messages, [])

class PureLogicTestCase(unittest.TestCase):
    """No MIDI hardware needed."""

    def test_splitchannel(self):
        self.assertEqual(rtmidi.splitchannel(0x90), (0x90, 0))
        self.assertEqual(rtmidi.splitchannel(0x9F), (0x90, 15))
        self.assertEqual(rtmidi.splitchannel(0xB3), (0xB0, 3))

    def test_msgtype2str(self):
        self.assertEqual(rtmidi.msgtype2str(rtmidi.NOTEON), 'NOTEON')
        self.assertEqual(rtmidi.msgtype2str(rtmidi.NOTEOFF), 'NOTEOFF')
        self.assertEqual(rtmidi.msgtype2str(rtmidi.CC), 'CC')
        self.assertEqual(rtmidi.msgtype2str(0x00), 'UNKNOWN')

    def test_midi2note(self):
        self.assertEqual(rtmidi.midi2note(60), 'C4')
        self.assertEqual(rtmidi.midi2note(69), 'A4')
        with self.assertRaises(ValueError):
            rtmidi.midi2note(128)
        with self.assertRaises(ValueError):
            rtmidi.midi2note(-1)

    def test_cents_pitchbend_roundtrip(self):
        self.assertEqual(rtmidi.cents2pitchbend(0), 8192)
        self.assertEqual(rtmidi.cents2pitchbend(-200), 0)
        self.assertEqual(rtmidi.cents2pitchbend(200), 16383)
        with self.assertRaises(ValueError):
            rtmidi.cents2pitchbend(201)
        with self.assertRaises(ValueError):
            rtmidi.pitchbend2cents(16384)
        with self.assertRaises(ValueError):
            rtmidi.pitchbend2cents(-1)

    def test_func_numargs(self):
        def cb2(msg, t):
            pass
        def cb3(src, msg, t):
            pass
        self.assertEqual(rtmidi._func_get_numargs(cb2), 2)
        self.assertEqual(rtmidi._func_get_numargs(cb3), 3)
        # bound method: self is bound, so 2 remaining args
        class C:
            def cb(self, msg, t):
                pass
        self.assertEqual(rtmidi._func_get_numargs(C().cb), 2)

    def test_send_validation_no_hardware(self):
        out = rtmidi.MidiOut()
        try:
            with self.assertRaises(ValueError):
                out.send_raw(0x90, 300, 0)
            with self.assertRaises(ValueError):
                out.send_raw(0x90, -1, 0)
            with self.assertRaises(ValueError):
                out.send_pitchbend(0, 16384)
            with self.assertRaises(ValueError):
                out.send_pitchbend(16, 8192)
            with self.assertRaises(ValueError):
                out.send_cc(0, 128, 0)
            with self.assertRaises(ValueError):
                out.send_noteon(0, 128, 64)
            with self.assertRaises(ValueError):
                out.send_messages(0x00, [(0, 60, 100)])
            with self.assertRaises(ValueError):
                out.send_noteon_many(0, [60], [64, 65])
            with self.assertRaises(TypeError):
                out.send_noteoff_many("bad", [60])
            with self.assertRaises(ValueError):
                out.send_sysex(128)
            # ranges are accepted wherever sequences are
            out.send_noteon_many(0, range(3), range(3))
            out.send_noteoff_many(0, range(3))
            out.send_messages(rtmidi.NOTEON, [(0, 60, 100)])
            with self.assertRaises(ValueError):
                rtmidi.MidiIn(queuesize=-1)
            with self.assertRaises(ValueError):
                rtmidi.MidiInMulti(queuesize=-1)
        finally:
            out.close_port()

    def test_ports_matching_validation(self):
        m = rtmidi.MidiIn()
        try:
            with self.assertRaises(TypeError):
                m.ports_matching(None)
        finally:
            m.close_port()

    def test_api_constant(self):
        self.assertTrue(hasattr(rtmidi, 'API_WEB_MIDI_API'))
        out = rtmidi.MidiOut()
        try:
            api = out.get_current_api()
            self.assertIsInstance(api, int)
        finally:
            out.close_port()


if __name__ == '__main__':
    unittest.main()
