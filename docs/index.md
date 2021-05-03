# Home

Welcome to the **rtmidi2** documentation!

**rtmidi2** is a wrapper for the C++ library [RtMidi](http://www.music.mcgill.ca/~gary/rtmidi/). It is written in cython, targets python 3 (>= 3.8 at the moment) and supports Linux, macOS and Windows. 

## RtMidi

RtMidi is a set of C++ classes (RtMidiIn, RtMidiOut and API-specific classes) that provides a common API for realtime MIDI input/output across Linux (ALSA & JACK), Macintosh OS X (CoreMIDI & JACK), and Windows (Multimedia Library) operating systems.

## Installation

Binary wheels are provided for all major platforms:

``` bash
pip install rtmidi2
```

## Quick Introduction

### Read incomming MIDI from default port

```python
from rtmidi2 import MidiIn, NOTEON, CC, splitchannel
midiin = MidiIn()
midiin.open_port()    # will get messages from the default port

def callback(msg: list, timestamp: float):
    # msg is a list of 1-byte strings
    # timestamp is a float with the time elapsed since last midi event
    msgtype, channel = splitchannel(msg[0])
    if msgtype == NOTEON:
        note, velocity = msg[1], msg[2]
        print(f"Noteon, {channel=}, {note=}, {velocity=}")
    elif msgtype == CC:
        cc, value = msg[1:]
        print(f"Control Change {channel=}, {cc=}, {value=}")
        
midiin.callback = callback

# The callback can be cancelled by setting it to None
midiin.callback = None

# When you are done, close the port
midiin.close_port()
```

### Create a port for other clients to send MIDI to

This will create a client named "clientA" with a port "inport". Messages
are received async via the given callback. Another client will send messages
to it

```python
from rtmidi2 import *
midiin = MidiIn("clientA")
midiin.open_virtual_port("inport")

def callback(msg, timestamp):
    # msg is a list of 1-byte strings
    # timestamp is a float with the time elapsed since last midi event
    msgtype, channel = splitchannel(msg[0])
    if msgtype == NOTEON:
        note, velocity = msg[1], msg[2]
        print(f"Noteon, {channel=}, {note=}, {velocity=}")
    elif msgtype == CC:
        cc, value = msg[1:]
        print(f"Control Change {channel=}, {cc=}, {value=}")

midiin.callback = callback

midiout = MidiOut("clientB")

# The name of the port will depend on the operating system and API used
# In Linux/ALSA, the port of clientA would appear as 'clientA:inport XXX:Y'
# We can use a glob pattern to match against the client and port names
midiout.open_port("clientA:inport*")

# Send a noteon C4 (midinote 60) with velocity 90 on channel 1
midiout.send_noteon(0, 60, 90)

# The callback will be called and print "noteon 60 90"
```

### Receive messages from multiple sources

With *rtmidi2* it is possible to listen to multiple sources simultaneously.

```python
from rtmidi2 import *

def callback_with_source(src, msg, time):
    msgtype, channel = splitchannel(msg[0])
    print(f"Message generated from {src}: {channel=}, {msgtype=}, data: {msg[1:]}")
    
midiin = MidiInMulti().open_ports("*")
midiin.callback = callback_with_source   

```

## Reference

See [reference](reference.md)

