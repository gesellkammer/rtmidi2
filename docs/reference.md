# Reference


---------


## MidiIn

### MidiIn


Create a MidiIn object


```python

class MidiIn(clientname: str, queuesize: int, api)

```


#### Example

```python
from rtmidi2 import MidiIn, NOTEON, CC, splitchannel
m_in = MidiIn()
m_in.open_port()    # will get messages from the default port

def callback(msg, timestamp):
    msgtype, channel = splitchannel(msg[0])
    if msgtype == NOTEON:
        note, velocity = msg[1], msg[2]
        print "noteon", note, velocity
    elif msgtype == CC:
        cc, value = msg[1:]
        print "control change", cc, value

m_in.callback = callback

# You can cancel the receiving of messages by setting the callback to None
m_in.callback = None

# When you are done, close the port
m_in.close_port()
```

!!! note 

    If you want to listen from multiple ports, use `MidiInMulti`

For blocking interface, use `midiin.get_message()`



**Args**

* **clientname** (`str`): an optional name for the client
* **queuesize** (`int`): the size of the queue in bytes.
* **api**: the api used (API_xxx)


---------


### Methods

#### \_\_init\_\_


Initialize self.  See help(type(self)) for accurate signature.


```python

def __init__(self, args, kwargs) -> None

```

----------

#### close\_port


Close an open port


```python

def close_port(self) -> None

```

----------

#### get\_message


Get a midi message (blocking)


```python

def get_message(self) -> None

```


For non-blocking interface, use the callback method (midiin.callback = ...)

A message can be:

* a 3 byte message (cc, noteon, pitchbend): `[(messagetype | channel), value1, value2]`
* a 2 byte message (progchange, chanpress): `[(messagetype | channel), value1]`
* a 1 byte message (start, stop, clock)
* a sysex message, with variable number of bytes

To isolate messagetype and channel, do this:

```python

messagetype = message[0] & 0xF0
channel     = message[0] & 0x0F

```

Or use the utility function splitchannel:

```python
msgtype, channel = splitchannel(message[0])
```

----------

#### get\_port\_name


Return name of given port number.


```python

def get_port_name(self, port, encoding) -> Any

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;the name of the port, or None if no port with the given index was found

----------

#### ignore\_types


Don't react to these messages.


```python

def ignore_types(self, midi_sysex, midi_time, midi_sense) -> None

```


This avoids having to make your callback aware of these and avoids congestion 
where your device acts as a midiclock but your not interested in that.

----------

#### open\_port


Open a port by index or name


```python

def open_port(self, port) -> None

```


!!! note

    The string can contain a glob pattern, in which case it will be
    matched against the existing ports and the first match will be used.
    An integer is the index to the list of available ports

##### Example

```python

from rtmidi2 import MidiIn
m = MidiIn().open_port("BCF*")
```

----------

#### open\_virtual\_port


Open a virtual port


```python

def open_virtual_port(self, port_name) -> None

```


##### Example

```python

from rtmidi2 import *
midiin = MidiIn("myapp")
midiin.open_virtual_port("myport")
```

----------

#### ports\_matching


Return the indexes of the ports which match the glob pattern


```python

def ports_matching(self, pattern) -> Any

```


##### Example

```python

# get all ports
from rtmidi2 import *
midiin = MidiIn()
allports = midiin.ports_matching("*")

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;a list of port indexes which match the given pattern


---------


### Attributes

**callback**

**deltatime**

**ports**: Returns a list with the names of the available ports

## MidiInMulti

### MidiInMulti


This class implements the capability to listen to multiple inputs at once


```python

class MidiInMulti(clientname: str, queuesize, api)

```


A callback needs to be defined, as in MidiIn, which will be called if any
of the devices receives any input.

Your callback can be of two forms:

```python

def callback(msg, time):
    msgtype, channel = splitchannel(msg[0])
    print msgtype, msg[1], msg[2]

def callback_with_source(src, msg, time):
    print "message generated from midi-device: ", src
    msgtype, channel = splitchannel(msg[0])
    print msgtype, msg[1], msg[2]

midiin = MidiInMulti().open_ports("*")
# your callback will be called according to its signature
midiin.callback = callback_with_source   
```

If you need to know the port number of the device initiating the message 
instead of the device name, use:

``` pyton
midiin.set_callback(callback_with_source, src_as_string=False)
```

#### Example

```python

multi = MidiInMulti().open_ports("*")
def callback(msg, timestamp):
    print(msg)
multi.callback = callback

```



**Args**

* **clientname** (`str`): an optional client name
* **queuesize**: the size of the queue in bytes
* **api**: the api used


---------


### Methods

#### \_\_init\_\_


Initialize self.  See help(type(self)) for accurate signature.


```python

def __init__(self, args, kwargs) -> None

```

----------

#### close\_port


returns 1 if OK, 0 if failed


```python

def close_port(self, port) -> None

```

----------

#### close\_ports


closes all ports and deactivates any callback.


```python

def close_ports(self) -> None

```

----------

#### get\_callback


MidiInMulti.get_callback(self)


```python

def get_callback(self) -> None

```

----------

#### get\_message


MidiInMulti.get_message(self, int gettime=1)


```python

def get_message(self, gettime) -> None

```

----------

#### get\_open\_ports


Returns a list of the open ports, by index


```python

def get_open_ports(self) -> Any

```


To get the name, use .get_port_name



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;a list with the indexes of the open ports

----------

#### get\_open\_ports\_byname


Similar to `get_open_ports`, returns a list of the open ports by name


```python

def get_open_ports_byname(self) -> Any

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;a list with the names of the open ports

----------

#### get\_port\_name


Return name of given port number.


```python

def get_port_name(self, portindex, encoding) -> Any

```


The port name is decoded to unicode with the encoding given by
``encoding`` (defaults to ``'utf-8'``). If ``encoding`` is ``None``,
return string un-decoded.



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;the port name (a str)

----------

#### open\_port


Low level interface to opening ports by index. Use open_ports to use a more


```python

def open_port(self, port) -> None

```


confortable API.

##### Example

```python
midiin.open_port(0)  # open the default port

# open all ports
for i in len(midiin.ports):
    midiin.open_port(i)

```

SEE ALSO: open_ports

----------

#### open\_ports


You can specify multiple patterns. Of course a pattern can also


```python

def open_ports(self, patterns, exclude) -> None

```


be an exact match

```pyton
# dont care to specify the full name of the Korg device
midiin.open_ports("BCF2000", "Korg*")
```

##### Example

```python

# Transpose all notes received one octave up,
# send them to a virtual port named "OUT"
midiin = MidiInMulti().open_ports("*")
midiout = MidiOut().open_virtual_port("OUT")
def callback(msg, timestamp):
    msgtype, ch = splitchannel(msg[0])
    if msgtype == NOTEON:
        midiout.send_noteon(ch,  msg[1] + 12, msg[2])
    elif msgtype == NOTEOFF:
        midiout.send_noteoff(ch, msg[1] + 12, msg[2])
midiin.callback = callback
```

----------

#### ports\_matching


Return the indexes of the ports which match the glob pattern


```python

def ports_matching(self, pattern, exclude) -> None

```


##### Example

```python
# get all ports
midiin.ports_matching("*")

# open the IAC port in OSX without having to remember the whole name
midiin.open_port(midiin.ports_matching("IAC*"))
```

----------

#### set\_callback


This is the same as `midiin.callback = mycallback`, but lets you specify how callback is called


```python

def set_callback(self, callback: function, src_as_string: bool) -> None

```


##### Example

```python
def callback_with_source(src, msg, time):
    print "message generated from midi-device: ", src
    msgtype, channel = splitchannel(msg[0])
    print(msgtype, msg[1], msg[2])

midiin = MidiInMulti()
midiin.open_ports("*")
# your callback will be called according to its signature
midiin.set_callback(callback_with_source)
```


---------


### Attributes

**callback**

**clientname**

**inspector**

**ports**

## MidiOut

### MidiOut


```python

class MidiOut()

```


---------


### Methods

#### \_\_init\_\_


Initialize self.  See help(type(self)) for accurate signature.


```python

def __init__(self, args, kwargs) -> None

```

----------

#### close\_port


Close an open port


```python

def close_port(self) -> None

```

----------

#### get\_current\_api


Return the low-level MIDI backend API used by this instance.


```python

def get_current_api(self) -> None

```


Use this by comparing the returned value to the module-level ``API_*``
constants

##### Example

```python
from rtmidi2 import *
midiout = rtmidi.MidiOut()
if midiout.get_current_api() == rtmidi.API_UNIX_JACK:
    print("Using JACK API for MIDI output.")
```

----------

#### get\_port\_name


Return name of given port number.


```python

def get_port_name(self, port, encoding) -> Any

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;the name of the port, or None if no port with the given index was found

----------

#### open\_port


Open a port by index or name


```python

def open_port(self, port) -> None

```


!!! note

    The string can contain a glob pattern, in which case it will be
    matched against the existing ports and the first match will be used.
    An integer is the index to the list of available ports

##### Example

```python

from rtmidi2 import MidiIn
m = MidiIn().open_port("BCF*")
```

----------

#### open\_virtual\_port


MidiOut.open_virtual_port(self, port_name)


```python

def open_virtual_port(self, port_name) -> None

```

----------

#### ports\_matching


Return the indexes of the ports which match the glob pattern


```python

def ports_matching(self, pattern) -> Any

```


##### Example

```python

# get all ports
from rtmidi2 import *
midiin = MidiIn()
allports = midiin.ports_matching("*")

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;a list of port indexes which match the given pattern

----------

#### send\_cc


Send a CC message


```python

def send_cc(self, channel, cc, value) -> None

```

----------

#### send\_messages


```python

def send_messages(self, messagetype, messages) -> None

```


| Message type | Value |
| ------------ | ----- |
| NOTEON       | 144   |
| CC           | 176   |
| NOTEOFF      | 128   |
| PROGCHANGE   | 192   |
| PITCHWHEEL   | 224   |


##### Example

```python
# send multiple noteoffs as noteon with velocity 0 for hosts which do not implement the noteoff message
from rtmidi2 import *
m = MidiOut()
m.open_port()
messages = [(0, i, 0) for i in range(127)]
m.send_messages(144, messages)
```

----------

#### send\_noteoff


Send a noteoff message


```python

def send_noteoff(self, channel, midinote) -> None

```

----------

#### send\_noteoff\_many


Send many noteoff messages at once


```python

def send_noteoff_many(self, channels, notes) -> None

```


!!! note

    A channel has a value between 0-15

----------

#### send\_noteon


Send a NOTEON message


```python

def send_noteon(self, channel, midinote, velocity) -> None

```

----------

#### send\_noteon\_many


Send many noteon messages at once


```python

def send_noteon_many(self, channel, notes, vels) -> None

```

----------

#### send\_pitchbend


Send a pitchbend message


```python

def send_pitchbend(self, channel, transp) -> None

```


!!! note

    The 0 point (no transposition) is 8192

The MIDI standard specifies a default of 2 semitones UP and 2 semitones DOWN for
the pitch-wheel. To convert cents to pitchbend (cents between -200 and 200), use
`cents2pitchbend`

**See Also**: `pitchbend2cents`, `cents2pitchbend`

----------

#### send\_raw


MidiOut.send_raw(self, *bytes)


```python

def send_raw(self, bytes) -> None

```

----------

#### send\_sysex


Send a sysex message


```python

def send_sysex(self, bytes) -> None

```


A sysex message consists of a starting byte 0xF0, the content of the sysex command,
and an end byte 0xF7. The bytes need to be in the range 0-127


---------


### Attributes

**ports**: Returns a list with the names of the available ports

## callback\_mididump


Use this function as your callback to dump all received messages


```python

def callback_mididump(msg: list[str], t) -> None

```


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


Convert cents to a pitchbend value


```python

def cents2pitchbend(cents, maxdeviation) -> int

```



**Args**

* **cents**: an integer between -maxdeviation and +maxdviation
* **maxdeviation**:

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`int`) The pitchbend value corresponding to the given cents


---------


## get\_in\_ports


Returns a list of available in ports


```python

def get_in_ports() -> list[str]

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[str]`) A list of available input ports, by name


---------


## get\_out\_ports


Returns a list of available out ports


```python

def get_out_ports() -> list[str]

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`list[str]`) A list of availabe output ports, by name


---------


## midi2note


convert a midinote to the string representation of the note


```python

def midi2note(midinote) -> str

```


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


Listen to all ports matching pattern and print the received messages


```python

def mididump(port_pattern: str = *, parsable: bool = False, api: int = 0
             ) -> MidiInMulti

```



**Args**

* **port_pattern** (`str`):  (default: *)
* **parsable** (`bool`): if True, it will return the data in comma delimited
    format         source, timedelta, msgtype, channel, byte2, byte3[, ...]
    (default: False)
* **api** (`int`): which api to use. In some platforms there is only one option
    (macOS, windows).  (default: 0)

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`MidiInMulti`) The MidiInMulti created to listen to all midi inputs


---------


## msgtype2str


Convert the message-type as returned by splitchannel(msg[0])[0] to a readable string


```python

def msgtype2str(msgtype) -> str

```


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


Convert a pitchbend value to cents


```python

def pitchbend2cents(pitchbend, maxcents) -> int

```



**Args**

* **pitchbend**: an integer between 0 and 16383
* **maxcents**: the max. cents deviation

**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`int`) The cents corresponding to the given pitchbend


---------


## splitchannel


Split the messagetype and the channel as returned by get_message


```python

def splitchannel(firstbyte) -> tuple[int, int]

```


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


---------


## version


Returns the version


```python

def version() -> tuple[int, int, int]

```



**Returns**

&nbsp;&nbsp;&nbsp;&nbsp;(`tuple[int, int, int]`) The version as (major, minor, patch)