# Reference


---------


## MidiBase

### 


```python

def () -> None

```


Base class for both MidiIn and MidiOut


Methods defined here are inherited and available for both midi input 
and output

**Attributes**

* **ports**: Returns a list with the names of the available ports


---------


**Methods**

### close\_port


```python

MidiBase.close_port(self)

```


Close an open port

----------

### get\_port\_name


```python

MidiBase.get_port_name(self, unsigned int port, encoding=u'utf-8')

```


Return name of given port number.



**Args**

* **port**: the port index
* **encoding**: the encoding used to decode the name

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`str | None`) The name of the port, or None if the port was not found

----------

### open\_port


```python

MidiBase.open_port(self, port=0)

```


Open a port by index or name


!!! note

    The string can contain a glob pattern, in which case it will be
    matched against the existing ports and the first match will be used.
    An integer is the index to the list of available ports

#### Example

```python

from rtmidi2 import MidiIn
m = MidiIn()
m.open_port("BCF*")
```



**Args**

* **port**: The port to open (an integer or a string)

----------

### open\_virtual\_port


```python

MidiBase.open_virtual_port(self, unicode port_name)

```


Open a virtual port


#### Example

```python

from rtmidi2 import *
midiin = MidiIn("myapp")
midiin.open_virtual_port("myport")
```



**Args**

* **port_name** (`str`): the name of the virtual port

----------

### ports\_matching


```python

MidiBase.ports_matching(self, unicode pattern)

```


Return the indexes of the ports which match the glob pattern


#### Example

```python

# get all ports
from rtmidi2 import *
midiin = MidiIn()
allports = midiin.ports_matching("*")

```



**Args**

* **pattern** (`str`): a glob pattern to match ports

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[int]`) a list of port indexes which match the given pattern


---------


## MidiIn

 - Base Class: [MidiBase](#midibase)

### 


```python

def (clientname: str, queuesize: int, api) -> None

```


Create a MidiIn object


#### Example

```python
from rtmidi2 import MidiIn, NOTEON, CC, splitchannel
m_in = MidiIn()
m_in.open_port()    # will get messages from the default port

def callback(msg, timestamp):
    msgtype, channel = splitchannel(msg[0])
    if msgtype == NOTEON:
        note, velocity = msg[1], msg[2]
        print("noteon", note, velocity)
    elif msgtype == CC:
        cc, value = msg[1:]
        print("control change", cc, value)

m_in.callback = callback

# You can cancel the receiving of messages by setting the callback to None
m_in.callback = None

# When you are done, close the port
m_in.close_port()
```

!!! note 

    If you want to receive messages from multiple ports, use `MidiInMulti`

For blocking interface, use `midiin.get_message()`



**Args**

* **clientname** (`str`): an optional name for the client
* **queuesize** (`int`): the size of the queue in bytes.
* **api**: the api used (API_xxx)

**Attributes**

* **callback**

* **deltatime**


---------


**Methods**

### get\_message


```python

MidiIn.get_message(self)

```


Get a midi message (blocking)


For non-blocking interface, use the callback method (midiin.callback = ...)

A message can be:

* a 3 byte message (cc, noteon, pitchbend): `[(messagetype | channel), value1, value2]`
* a 2 byte message (progchange, chanpress): `[(messagetype | channel), value1]`
* a 1 byte message (start, stop, clock)
* a sysex message, with variable number of bytes

To isolate messagetype and channel:

```python

messagetype = message[0] & 0xF0
channel     = message[0] & 0x0F

```

Or use the utility function `splitchannel`, which does the same:

```python
msgtype, channel = splitchannel(message[0])
```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[int] | None`) Returns a list of ints between 0-255

----------

### ignore\_types


```python

MidiIn.ignore_types(self, midi_sysex=True, midi_time=True, midi_sense=True)

```


Don't react to these messages.


This avoids having to make your callback aware of these and avoids congestion 
where your device acts as a midiclock but your not interested in that.



**Args**

* **midi_sysex**: if True, sysex messages are ignored
* **midi_time**: if True, midi time messages are ignored
* **midi_sense**: if True, midi sense messages are ignored


---------


## MidiOut

 - Base Class: [MidiBase](#midibase)

### 


```python

MidiOut(clientname=None, api=API_UNSPECIFIED)

```


---------


**Methods**

### get\_current\_api


```python

MidiOut.get_current_api(self)

```


Return the low-level MIDI backend API used by this instance.


Use this by comparing the returned value to the module-level ``API_*``
constants

#### Example

```python
from rtmidi2 import *
midiout = rtmidi.MidiOut()
if midiout.get_current_api() == rtmidi.API_UNIX_JACK:
    print("Using JACK API for MIDI output.")
```

----------

### open\_virtual\_port


```python

def open_virtual_port(self, port_name) -> None

```


MidiOut.open_virtual_port(self, unicode port_name)



**Args**

* **port_name**:

----------

### send\_cc


```python

MidiOut.send_cc(self, unsigned char channel, unsigned char cc, unsigned char value)

```


Send a CC message



**Args**

* **channel**: 0-15
* **cc**: the CC index (0-127)
* **value**: the CC value (0-127)

----------

### send\_messages


```python

MidiOut.send_messages(self, int messagetype, messages)

```


| Message type | Value |
| ------------ | ----- |
| NOTEON       | 144   |
| CC           | 176   |
| NOTEOFF      | 128   |
| PROGCHANGE   | 192   |
| PITCHWHEEL   | 224   |


#### Example

```python
# send multiple noteoffs as noteon with velocity 0 for hosts which do not implement the noteoff message
from rtmidi2 import *
m = MidiOut()
m.open_port()
messages = [(0, i, 0) for i in range(127)]
m.send_messages(144, messages)
```



**Args**

* **messagetype**: an integer identifying the kind of message
* **messages**: a list of tuples of the form `(channel, value1, value2)`

----------

### send\_noteoff


```python

MidiOut.send_noteoff(self, unsigned char channel, unsigned char midinote)

```


Send a noteoff message



**Args**

* **channel**: 0-15
* **midinote**: the midinote to stop

----------

### send\_noteoff\_many


```python

MidiOut.send_noteoff_many(self, channels, notes)

```


Send many noteoff messages at once


!!! note

    A channel has a value between 0-15



**Args**

* **channels**: a list of channels, or a single integer channel
* **notes**: a list of midinotes to be released

----------

### send\_noteon


```python

MidiOut.send_noteon(self, unsigned char channel, unsigned char midinote, unsigned char velocity)

```


Send a NOTEON message



**Args**

* **channel**: 0-15
* **midinote**: a midinote (0-127)
* **velocity**: velocity (0-127)

----------

### send\_noteon\_many


```python

MidiOut.send_noteon_many(self, channel, notes, vels)

```


Send many noteon messages at once



**Args**

* **channel**: an integer indicating the midi channel, or a list of channels
    (must be the same length as notes)
* **notes**: a list of midinotes
* **vels**: a list of velocities

----------

### send\_pitchbend


```python

MidiOut.send_pitchbend(self, unsigned char channel, unsigned int transp)

```


Send a pitchbend message


!!! note

    The 0 point (no transposition) is 8192

The MIDI standard specifies a default of 2 semitones UP and 2 semitones DOWN for
the pitch-wheel. To convert cents to pitchbend (cents between -200 and 200), use
`cents2pitchbend`

**See Also**: `pitchbend2cents`, `cents2pitchbend`



**Args**

* **channel**: 0-15
* **transp**:

----------

### send\_raw


```python

def send_raw(self, bytes) -> None

```


MidiOut.send_raw(self, *bytes)



**Args**

* **bytes**:

----------

### send\_sysex


```python

MidiOut.send_sysex(self, *bytes)

```


Send a sysex message


A sysex message consists of a starting byte 0xF0, the content of the sysex command,
and an end byte 0xF7. The bytes need to be in the range 0-127



**Args**

* **bytes**: the content of the sysex message.


---------


## MidiInMulti

### 


```python

MidiInMulti(clientname=None, queuesize=1024, Api api=UNSPECIFIED)

```


This class implements the capability to listen to multiple inputs at once


A callback needs to be defined, as in MidiIn, which will be called if any
of the devices receives any input.

Your callback can be of two forms:

```python

def callback(msg, time):
    msgtype, channel = splitchannel(msg[0])
    print(msgtype, msg[1], msg[2])

def callback_with_source(src, msg, time):
    print("message generated from midi-device: ", src)
    msgtype, channel = splitchannel(msg[0])
    print(msgtype, msg[1], msg[2])

midiin = MidiInMulti()
midiin.open_ports("*")

# The callback will be called according to its signature
midiin.callback = callback_with_source   
```

If you need to know the port number of the device initiating the message 
instead of the device name, use:

``` pyton
midiin.set_callback(callback_with_source, src_as_string=False)
```

#### Example

```python

multi = MidiInMulti()
multi.open_ports("*")

def callback(msg, timestamp):
    print(msg)

multi.callback = callback

```



**Args**

* **clientname** (`str`): an optional client name
* **queuesize**: the size of the queue in bytes
* **api**: the api used

**Attributes**

* **callback**

* **clientname**

* **inspector**

* **ports**


---------


**Methods**

### close\_port


```python

MidiInMulti.close_port(self, unsigned int port) -> int

```


Close the given port


Returns: 1 if port was succesfully closed, 0 if failed



**Args**

* **port** (`int`): the index of the port to close

----------

### close\_ports


```python

MidiInMulti.close_ports(self) -> int

```


closes all ports and deactivates any callback.

----------

### get\_callback


```python

MidiInMulti.get_callback(self)

```


Returns the python callback of this MidiIn

----------

### get\_message


```python

def get_message(self, gettime) -> None

```


MidiInMulti.get_message(self, int gettime=1)



**Args**

* **gettime**:

----------

### get\_open\_ports


```python

MidiInMulti.get_open_ports(self)

```


Returns a list of the open ports, by index


To get the name, use .get_port_name



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;a list with the indexes of the open ports

----------

### get\_open\_ports\_byname


```python

MidiInMulti.get_open_ports_byname(self)

```


Similar to `get_open_ports`, returns a list of the open ports by name



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[str]`) a list with the names of the open ports

----------

### get\_port\_name


```python

MidiInMulti.get_port_name(self, int portindex, encoding=u'utf-8')

```


Return name of given port number.


The port name is decoded to unicode with the encoding given by
``encoding`` (defaults to ``'utf-8'``). If ``encoding`` is ``None``,
return string un-decoded.



**Args**

* **portindex**: the index of the port
* **encoding**: the encoding used to convert the name to a str

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`str`) The port name

----------

### open\_port


```python

MidiInMulti.open_port(self, unsigned int port)

```


Low level interface to opening ports by index. Use open_ports to use a more


confortable API.

#### Example

```python
midiin.open_port(0)    # open the default port

# open all ports
for i in len(midiin.ports):
    midiin.open_port(i)

```

#### See Also

open_ports



**Args**

* **port** (`int`): the index of the port to open

----------

### open\_ports


```python

MidiInMulti.open_ports(self, *patterns, exclude=None)

```


You can specify multiple patterns. Of course a pattern can also


be an exact match

```pyton
# dont care to specify the full name of the Korg device
midiin.open_ports("BCF2000", "Korg*")
```

#### Example

```python

# Transpose all notes received one octave up,
# send them to a virtual port named "OUT"
midiin = MidiInMulti()
midiin.open_ports("*")

midiout = MidiOut()
midiout.open_virtual_port("OUT")

def callback(msg, timestamp):
    msgtype, ch = splitchannel(msg[0])
    if msgtype == NOTEON:
        midiout.send_noteon(ch,  msg[1] + 12, msg[2])
    elif msgtype == NOTEOFF:
        midiout.send_noteoff(ch, msg[1] + 12, msg[2])

midiin.callback = callback
```



**Args**

* **patterns**: all ports matching any of the patterns will be opened
* **exclude**: an optional exclude pattern

----------

### ports\_matching


```python

MidiInMulti.ports_matching(self, pattern, exclude=None)

```


Return the indexes of the ports which match the glob pattern


#### Example

```python

# open the IAC port in OSX without having to remember the whole name
from rtmidi2 import MidiInMulti
midiin = MidiInMulti()
midiin.open_port(midiin.ports_matching("IAC*"))
```



**Args**

* **pattern**: an exact name or a glob patter (str)
* **exclude**: a glob pattern to exclude

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[int]`) A list with the indexes of the ports matching the given pattern

----------

### set\_callback


```python

MidiInMulti.set_callback(self, callback, src_as_string=True)

```


This is the same as `midiin.callback = mycallback`, but lets you specify how callback is called


#### Example

```python
def callback_with_source(src, msg, time):
    print("message generated from midi-device: ", src)
    msgtype, channel = splitchannel(msg[0])
    print(msgtype, msg[1], msg[2])

midiin = MidiInMulti()
midiin.open_ports("*")
# your callback will be called according to its signature
midiin.set_callback(callback_with_source)
```



**Args**

* **callback** (`function`): your callback. A function of the form
    `func(msg, time)` or `func(src, msg, time)`, where **msg** is a         a
    tuple of bytes, normally three, **time** is the timestamp of the
    received msg and **src** is an int or a str identifying the src from
    which the msg was received (see src_as_string)
* **src_as_string** (`bool`): This only applies for the case where your
    callback is `func(src, msg, time)`. In this case, if src_as_string is True,
    the source is the string representing the source. Otherwise, it is the port
    number.


---------


## callback\_mididump


```python

callback_mididump(list msg, float t)

```


Use this function as your callback to dump all received messages


### Example

```python

from rtmidi2 import *

client = MidiIn("myclient")
client.open_virtual_port("myport")
client.callback = callback_mididump
```



**Args**

* **msg** (`list[str]`): this will hold the data
* **t**: the time delta since last message


---------


## cents2pitchbend


```python

cents2pitchbend(int cents, int maxdeviation=200) -> int

```


Convert cents to a pitchbend value



**Args**

* **cents**: an integer between -maxdeviation and +maxdviation
* **maxdeviation**:

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`int`) The pitchbend value corresponding to the given cents


---------


## get\_in\_ports


```python

get_in_ports()

```


Returns a list of available in ports



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[str]`) A list of available input ports, by name


---------


## get\_out\_ports


```python

get_out_ports()

```


Returns a list of available out ports



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[str]`) A list of availabe output ports, by name


---------


## midi2note


```python

midi2note(int midinote)

```


convert a midinote to the string representation of the note


### Example

```python
>>> midi2note(60)
C4
```



**Args**

* **midinote**: the midinote to convert

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`str`) the corresponding note name


---------


## mididump


```python

mididump(port_pattern=u'*', parsable=False, api=API_UNSPECIFIED)

```


Listen to all ports matching pattern and print the received messages



**Args**

* **port_pattern** (`str`):  (*default*: `*`)
* **parsable** (`bool`): if True, it will return the data in comma delimited
    format         source, timedelta, msgtype, channel, byte2, byte3[, ...]
    (*default*: `False`)
* **api** (`int`): which api to use. In some platforms there is only one option
    (macOS, windows).  (*default*: `0`)

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`MidiInMulti`) The MidiInMulti created to listen to all midi inputs


---------


## msgtype2str


```python

msgtype2str(int msgtype)

```


Convert the message-type as returned by splitchannel(msg[0])[0] to a readable string


### Example

```python
>>> msg = midiin.get_message()
>>> msgtype, channel = splitchannel(msg[0])
>>> msgtype2str(msgtype)
NOTEON
```

**See Also**: `splitchannel`



**Args**

* **msgtype**: the type of the message (an integer)

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`str`) the name of the message


---------


## pitchbend2cents


```python

pitchbend2cents(int pitchbend, maxcents=200) -> int

```


Convert a pitchbend value to cents



**Args**

* **pitchbend**: an integer between 0 and 16383
* **maxcents**: the max. cents deviation

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`int`) The cents corresponding to the given pitchbend


---------


## splitchannel


```python

splitchannel(int firstbyte) -> tuple

```


Split the messagetype and the channel as returned by get_message


```python
msg = midiin.get_message()
msgtype, channel = splitchannel(msg[0])
```

**See Also**: `msgtype2str`



**Args**

* **firstbyte**: the first byte of a MIDI message, which consists         of the
    msgtype and the channel ORed together

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`tuple[int, int]`) A tuple `(msgtype: int, channel: int)`, where the channel is a value 0-15