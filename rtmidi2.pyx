# cython: binding=True
# cython: boundscheck=False
# cython: embedsignature=True
# cython: checknone=False
# cython: language_level=3

### cython imports
from libcpp.string cimport string
from libcpp.vector cimport vector
from cython.operator cimport dereference as deref, preincrement as inc

cdef extern from "Python.h":
    void PyEval_InitThreads()
#from libc.stdlib cimport malloc, free

import inspect
import fnmatch

# Init Python threads and GIL, because RtMidi calls Python from native threads.
# See http://permalink.gmane.org/gmane.comp.python.cython.user/5837
PyEval_InitThreads()

### constants
DEF DNOTEON     = 144
DEF DCC         = 176
DEF DNOTEOFF    = 128
DEF DPROGCHANGE = 192
DEF DPITCHWHEEL = 224
DEF QUEUESIZE   = 1024

NOTEON     = DNOTEON
CC         = DCC
NOTEOFF    = DNOTEOFF
PROGCHANGE = DPROGCHANGE
PITCHWHEEL = DPITCHWHEEL

_midiin = None

cdef list _notenames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "Bb", "B", "C"]
cdef dict MSGTYPES = {
    NOTEON:     'NOTEON',
    NOTEOFF:    'NOTEOFF',
    CC:         'CC',
    PITCHWHEEL: 'PITCHWHEEL',
    PROGCHANGE: 'PROGCHANGE'
}

cdef extern from "RtMidi/RtMidi.h" namespace "RtMidi":
    cdef enum Api "RtMidi::Api":
        UNSPECIFIED  "RtMidi::UNSPECIFIED"
        MACOSX_CORE  "RtMidi::MACOSX_CORE"
        LINUX_ALSA   "RtMidi::LINUX_ALSA"
        UNIX_JACK    "RtMidi::UNIX_JACK"
        WINDOWS_MM   "RtMidi::WINDOWS_MM"
        RTMIDI_DUMMY "RtMidi::RTMIDI_DUMMY"

API_UNSPECIFIED = UNSPECIFIED
API_MACOSX_CORE = MACOSX_CORE
API_LINUX_ALSA = LINUX_ALSA
API_UNIX_JACK = UNIX_JACK
API_WINDOWS_MM = WINDOWS_MM
API_RTMIDI_DUMMY = RTMIDI_DUMMY

### C++ interface
cdef extern from "RtMidi/RtMidi.h":
    ctypedef void (*RtMidiCallback)(double timeStamp, vector[unsigned char]* message, void* userData)
    cdef cppclass RtMidi:
        void openPort(unsigned int portNumber) except+
        void openVirtualPort(string portName) except+
        unsigned int getPortCount()
        string getPortName(unsigned int portNumber) except+
        void closePort() except+

    cdef cppclass RtMidiIn(RtMidi):
        RtMidiIn(RtMidi.Api api, string clientName, unsigned int queueSizeLimit) except+
        void setCallback(RtMidiCallback callback, void* userData) except+
        void cancelCallback() except+
        void ignoreTypes(bint midiSysex, bint midiTime, bint midiSense)
        double getMessage(vector[unsigned char]* message) except+

    cdef cppclass RtMidiOut(RtMidi):
        RtMidiOut(RtMidi.Api api, string clientName) except+
        # RtMidiOut()
        void sendMessage(vector[unsigned char]* message) except+
        Api getCurrentApi()

cdef class MidiBase:
    """
    Base class for both MidiIn and MidiOut

    Methods defined here are inherited and available for both midi input 
    and output

    """
    cdef readonly list _openedports
    # Private
    cdef RtMidi* baseptr(self):
        return NULL

    # Public
    def open_port(self, port=0):
        """
        Open a port by index or name

        Args:
            port: The port to open (an integer or a string)

        Returns:
            None

        !!! note

            The string can contain a glob pattern, in which case it will be
            matched against the existing ports and the first match will be used.
            An integer is the index to the list of available ports

        Example
        -------

        ```python
        
        from rtmidi2 import MidiIn
        m = MidiIn()
        m.open_port("BCF*")
        ```

        """
        if isinstance(port, int):
            if port > len(self.ports) - 1:
                raise ValueError("port number out of range")
            port_number = port
        else:
            ports = self.ports
            if port in ports:
                port_number = self.ports.index(port)
            else:
                match = self.ports_matching(port)
                if match:
                    return self.open_port(match[0])
                else:
                    raise ValueError("Port not found")
        self.baseptr().openPort(port_number)
        if self._openedports is None:
            self._openedports = []
        self._openedports.append(port_number)
       
    def get_port_name(self, unsigned int port, encoding='utf-8'):
        """
        Return name of given port number.

        Args:
            port: the port index
            encoding: the encoding used to decode the name

        Returns:
            (str | None) The name of the port, or None if the port was not found
        
        """
        cdef string name = self.baseptr().getPortName(port)
        if len(name):
            if encoding:
                # XXX: kludge, there seems to be a bug in RtMidi as it returns
                # improperly encoded strings from getPortName with some
                # backends, so we just ignore decoding errors
                return name.decode(encoding, errors="ignore")
            else:
                return name
        else:
            return None

    @property 
    def ports(self):
        """
        Returns a list with the names of the available ports
        """
        return [self.get_port_name(index) for index in range(self.baseptr().getPortCount())]

    def open_virtual_port(self, str port_name):
        """
        Open a virtual port

        Args:
            port_name (str): the name of the virtual port

        Returns:
            None

        Example
        -------

        ```python

        from rtmidi2 import *
        midiin = MidiIn("myapp")
        midiin.open_virtual_port("myport")
        ```

        """
        self._openedports.append(port_name)
        cdef bytes bport = port_name.encode('ASCII', errors='ignore')
        self.baseptr().openVirtualPort(string(<char*>bport))
        
    def close_port(self):
        """
        Close an open port
        """
        self.baseptr().closePort()

    def ports_matching(self, str pattern):
        """
        Return the indexes of the ports which match the glob pattern

        Args:
            pattern (str): a glob pattern to match ports

        Returns:
            (list[int]) a list of port indexes which match the given pattern


        Example
        -------

        ```python

        # get all ports
        from rtmidi2 import *
        midiin = MidiIn()
        allports = midiin.ports_matching("*")
        
        ```
        """
        assert pattern is not None
        ports = self.ports
        return [i for i, port in enumerate(ports) if fnmatch.fnmatch(port, pattern)]


# ---- Callbacks ----
cdef void midi_in_callback(double time_stamp, vector[unsigned char]* message_vector, void* py_callback) with gil:
    cdef list message = [message_vector.at(i) for i in range(message_vector.size())]
    (<object>py_callback)(message, time_stamp)


cdef void midi_in_callback_with_src(double time_stamp, vector[unsigned char]* message_vector, void* pythontuple) with gil:
    message = [message_vector.at(i) for i in range(message_vector.size())]
    portname, callback = <tuple>pythontuple
    callback(portname, message, time_stamp)


cdef class MidiIn(MidiBase):
    """
    Create a MidiIn object
    
    Args:
        clientname (str): an optional name for the client
        queuesize (int): the size of the queue in bytes.
        api: the api used (API_xxx)

    Example
    -------

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
    """
    
    cdef RtMidiIn* thisptr
    cdef object py_callback
    cdef readonly double deltatime

    def __cinit__(self, clientname=None, unsigned int queuesize=QUEUESIZE, Api api=UNSPECIFIED):
        if clientname is None:
            self.thisptr = new RtMidiIn(api, string(<char*>"RTMIDI"), queuesize)
        else:
            assert isinstance(clientname, str)
            bclientname = clientname.encode("ASCII", errors="ignore")
            self.thisptr = new RtMidiIn(api, string(<char*>bclientname), queuesize)
        self.py_callback = None
        self._openedports = []

    def __dealloc__(self):
        self.py_callback = None
        del self.thisptr

    cdef RtMidi* baseptr(self):
        return self.thisptr

    property callback:
        def __get__(self):
            """The python function called when a message is received"""
            return self.py_callback

        def __set__(self, callback):
            if callback is None:
                self._cancel_callback()
            else:
                self._set_callback(callback)

    cdef void _cancel_callback(self):
        """cancel a previously set callback. Does nothing if callback was not set"""
        if self.py_callback is not None:
            self.thisptr.cancelCallback()
            self.py_callback = None

    cdef void _set_callback(self, callback):
        """set callback. If already set, cancels previous callback"""
        if self.py_callback is not None:
            self._cancel_callback()
        self.py_callback = callback
        self.thisptr.setCallback(midi_in_callback, <void*>callback)

    def ignore_types(self, midi_sysex=True, midi_time=True, midi_sense=True):
        """
        Don't react to these messages. 

        This avoids having to make your callback aware of these and avoids congestion 
        where your device acts as a midiclock but your not interested in that.

        Args:
            midi_sysex: if True, sysex messages are ignored
            midi_time: if True, midi time messages are ignored
            midi_sense: if True, midi sense messages are ignored

        Returns:
            None
        """
        self.thisptr.ignoreTypes(midi_sysex, midi_time, midi_sense)

    def get_message(self):
        """
        Get a midi message (blocking)

        For non-blocking interface, use the callback method (midiin.callback = ...)

        Returns:
            (list[int] | None) Returns a list of ints between 0-255

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
        """
        cdef vector[unsigned char]* message_vector = new vector[unsigned char]()
        cdef double deltatime = self.thisptr.getMessage(message_vector)
        cdef list message
        self.deltatime = deltatime
        if not message_vector.empty():
            message = [message_vector.at(i) for i in range(message_vector.size())]
            return message
        else:
            return None


cdef class MidiInMulti:
    """
    This class implements the capability to listen to multiple inputs at once
    A callback needs to be defined, as in MidiIn, which will be called if any
    of the devices receives any input.

    Args:
        clientname (str): an optional client name
        queuesize: the size of the queue in bytes
        api: the api used

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

    Example
    -------

    ```python

    multi = MidiInMulti()
    multi.open_ports("*")

    def callback(msg, timestamp):
        print(msg)
    
    multi.callback = callback
    
    ```
    """
    
    cdef vector[RtMidiIn *]* ptrs
    cdef int queuesize
    cdef Api api
    cdef readonly object clientname
    cdef object py_callback
    cdef list qualified_callbacks
    cdef readonly list _openedports
    cdef dict hascallback
    
    property inspector:
        def __get__(self):
            return MidiIn("INSPECTOR")

    def __cinit__(self, clientname=None, queuesize=QUEUESIZE, Api api=UNSPECIFIED):
        self.ptrs = new vector[RtMidiIn *]()
        self.py_callback = None
        self.qualified_callbacks = []
        self.api = api

    def __init__(self, clientname=None, queuesize=QUEUESIZE, Api api=UNSPECIFIED):
        self.queuesize = queuesize
        self._openedports = []
        self.hascallback = {}
        if clientname is None:
            clientname = "RTMIDI"
        self.clientname = clientname.encode("ASCII", errors="ignore")

    def __dealloc__(self):
        self.close_ports()
        del self.ptrs

    def __repr__(self):
        allports = self.ports
        s = " + ".join(allports[port] for port in self._openedports)
        return "MidiInMulti ( %s )" % s

    property ports:
        def __get__(self):
            return self.inspector.ports

    def get_open_ports(self):
        """
        Returns a list of the open ports, by index
        To get the name, use .get_port_name

        Returns:
            a list with the indexes of the open ports
        """
        return self._openedports

    def get_open_ports_byname(self):
        """
        Similar to `get_open_ports`, returns a list of the open ports by name

        Returns:
            (list[str]) a list with the names of the open ports
        """
        return [self.get_port_name(idx) for idx in self.get_open_ports()]

    def get_port_name(self, int portindex, encoding="utf-8"):
        """
        Return name of given port number.

        Args:
            portindex: the index of the port
            encoding: the encoding used to convert the name to a str

        Returns:
            (str) The port name 

        The port name is decoded to unicode with the encoding given by
        ``encoding`` (defaults to ``'utf-8'``). If ``encoding`` is ``None``,
        return string un-decoded.
        """
        return self.inspector.get_port_name(portindex, encoding)

    def get_callback(self):
        """Returns the python callback of this MidiIn"""
        return self.py_callback

    def ports_matching(self, pattern, exclude=None):
        """
        Return the indexes of the ports which match the glob pattern

        Args:
            pattern: an exact name or a glob patter (str)
            exclude: a glob pattern to exclude

        Returns:
            (list[int]) A list with the indexes of the ports matching the
            given pattern

        Example
        -------

        ```python
        
        # open the IAC port in OSX without having to remember the whole name
        from rtmidi2 import MidiInMulti
        midiin = MidiInMulti()
        midiin.open_port(midiin.ports_matching("IAC*"))
        ```
        """
        ports = self.ports
        if exclude is None:
            return [i for i, port in enumerate(ports) if fnmatch.fnmatch(port, pattern)]
        else:
            return [i for i, port in enumerate(ports) if fnmatch.fnmatch(port, pattern) and not fnmatch.fnmatch(port, exclude)]

    cpdef open_port(self, unsigned int port):
        """
        Low level interface to opening ports by index. Use open_ports to use a more
        confortable API.

        Args:
            port (int): the index of the port to open

        Returns:
            None

        ## Example
        
        ```python
        midiin.open_port(0)    # open the default port

        # open all ports
        for i in len(midiin.ports):
            midiin.open_port(i)

        ```

        ## See Also
        
        open_ports
        """
        if port >= len(self.inspector.ports):
            raise ValueError("Port out of range")
        if port in self._openedports:
            raise ValueError("Port already open!")
        cdef RtMidiIn* newport = new RtMidiIn(self.api, string(<char*>self.clientname), self.queuesize)
        newport.openPort(port)
        self.ptrs.push_back(newport)
        self._openedports.append(port)
        # a new open port should be assigned a callback if this was already set
        if self.py_callback is not None:
            callback = self.py_callback
            self._cancel_callbacks()
            self.callback = callback
        
    def open_ports(self, *patterns, exclude=None):
        """
        You can specify multiple patterns. Of course a pattern can also
        be an exact match

        Args:
            patterns: all ports matching any of the patterns will be opened
            exclude: an optional exclude pattern

        Returns:
            None

        ```pyton
        # dont care to specify the full name of the Korg device
        midiin.open_ports("BCF2000", "Korg*")
        ```

        ## Example
        
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
        """
        for pattern in patterns:
            for port in self.ports_matching(pattern, exclude):
                self.open_port(port)
        
    cpdef int close_ports(self):
        """closes all ports and deactivates any callback."""
        cdef RtMidiIn* ptr
        for i, port_index in enumerate(self._openedports):
            ptr = self.ptrs.at(i)
            port = self._openedports[i]
            if self.hascallback.get(port, False):
                ptr.cancelCallback()
            ptr.closePort()
        self.hascallback = {}
        self.ptrs.clear()
        self._openedports = []
        return 1

    cpdef int close_port(self, unsigned int port):
        """
        Close the given port

        Args:
            port (int): the index of the port to close

        Returns: 1 if port was succesfully closed, 0 if failed
        """
        if port not in self._openedports:
            return 0
        cdef int port_index = self._openedports.index(port)
        cdef RtMidiIn* ptr = self.ptrs.at(port_index)
        if self.hascallback.get(port_index, False):
            ptr.cancelCallback()
        ptr.closePort()
        self.ptrs.erase(self.ptrs.begin()+port_index)
        self._openedports.pop(port_index)
        return 1

    property callback:
        def __get__(self):
            return self.py_callback
        def __set__(self, callback):
            cdef RtMidiIn* ptr
            if callback is None:
                self._cancel_callbacks()
            else:
                numargs = _func_get_numargs(callback)
                if numargs == 3:
                    self._set_qualified_callback(callback)
                    return
                if not (numargs == 2 or (numargs is None and callable(callback))):
                    raise TypeError("callback should be a callable function of the form func(msg, time) or func(src, msg, time)")
                self.py_callback = callback
                for i in range(self.ptrs.size()):
                    ptr = self.ptrs.at(i)
                    port = self._openedports[i]
                    if self.hascallback.get(port, False):
                        ptr.cancelCallback()
                    if callback is not None:
                        ptr.setCallback(midi_in_callback, <void*>callback)
                        self.hascallback[port] = True

    def _cancel_callbacks(self):
        cdef RtMidiIn* ptr
        for i in range(self.ptrs.size()):
            ptr = self.ptrs.at(i)
            port = self._openedports[i]
            if self.hascallback.get(port, False):
                ptr.cancelCallback()
                self.hascallback[port] = False
        self.py_callback = None

    def set_callback(self, callback, src_as_string=True):
        """
        This is the same as `midiin.callback = mycallback`, but lets you specify how callback is called

        Args:
            callback (function) : your callback. A function of the form
                `func(msg, time)` or `func(src, msg, time)`, where **msg** is a
                a tuple of bytes, normally three, **time** is the timestamp of the 
                received msg and **src** is an int or a str identifying the src from
                which the msg was received (see src_as_string)
            src_as_string (bool): This only applies for the case where your 
                callback is `func(src, msg, time)`. In this case, if src_as_string is True,
                the source is the string representing the source. Otherwise, it is the port number.

        Returns:
            None


        Example
        -------

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
        """
        numargs = _func_get_numargs(callback)
        if numargs == 2:
            self.callback = callback
        elif numargs == 3:
            self._set_qualified_callback(callback, src_as_string)
        else:
            raise ValueError("callback must have either the signature f(msg, time) or f(src, msg, time)")
    
    def _set_qualified_callback(self, callback, src_as_string=True):
        """
        this callback will be called with src, msg, time

        where:
            src  is the integer identifying the in-port or the string name if src_as_string is True. The string is: midiin.ports[src]
            msg  is a 3 byte midi message
            time is the time identifier of the message
        """
        cdef RtMidiIn* ptr
        self.py_callback = callback
        self.qualified_callbacks = []
        for i in range(self.ptrs.size()):
            ptr = self.ptrs.at(i)
            port = self._openedports[i]
            if self.hascallback.get(port, False):
                ptr.cancelCallback()
            if callback is not None:
                if not src_as_string:
                    tup = (port, callback)
                else:
                    tup = (self.get_port_name(port), callback)
                self.qualified_callbacks.append(tup)
                ptr.setCallback(midi_in_callback_with_src, <void*>tup)
                self.hascallback[port] = True

    def get_message(self, int gettime=1):
        raise NotImplemented("The blocking interface is not implemented for multiple "
                             "inputs. Use the callback system")


##########################################
#              UTILITIES
##########################################

cpdef tuple splitchannel(int firstbyte):
    """
    Split the messagetype and the channel as returned by get_message

    Args:
        firstbyte: the first byte of a MIDI message, which consists
            of the msgtype and the channel ORed together 

    Returns:
        (tuple[int, int]) A tuple `(msgtype: int, channel: int)`, where the 
        channel is a value 0-15

    ```python
    msg = midiin.get_message()
    msgtype, channel = splitchannel(msg[0])
    ```
    
    **See Also**: `msgtype2str`
    """
    return firstbyte & 0xF0, firstbyte & 0x0F

def _func_get_numargs(func):
    try:
        spec = inspect.getargspec(func)
        numargs = sum(1 for a in spec.args if a is not "self")
        return numargs
    except TypeError:
        return None

def msgtype2str(int msgtype):
    """
    Convert the message-type as returned by splitchannel(msg[0])[0] to a readable string

    Args:
        msgtype: the type of the message (an integer)

    Returns:
        (str) the name of the message
    

    Example
    -------

    ```python
    >>> msg = midiin.get_message()
    >>> msgtype, channel = splitchannel(msg[0])
    >>> msgtype2str(msgtype)
    NOTEON
    ```

    **See Also**: `splitchannel`
    """
    return MSGTYPES.get(msgtype, 'UNKNOWN')


def midi2note(int midinote):
    """
    convert a midinote to the string representation of the note

    Args:
        midinote: the midinote to convert

    Returns:
        (str) the corresponding note name

    Example
    -------
    
    ```python
    >>> midi2note(60)
    C4
    ```
    """
    cdef int octave = int(midinote / 12) - 1
    cdef int pitchindex = midinote % 12
    return "%s%d" % (_notenames[pitchindex], octave)


def callback_mididump(list msg, float t):
    """
    Use this function as your callback to dump all received messages 

    Args:
        msg (list[str]): this will hold the data
        t: the time delta since last message

    Example
    -------

    ```python

    from rtmidi2 import *

    client = MidiIn("myclient")
    client.open_virtual_port("myport")
    client.callback = callback_mididump
    ```
    """
    msgt, ch = splitchannel(msg[0])
    msgtstr = msgtype2str(msgt)
    val1 = int(msg[1])
    val2 = int(msg[2])
    if msgt == CC:
        print("CC      ch:%02d  %03d -> %03d" % (ch, val1, val2))
    elif msgt == NOTEON or msgt == NOTEOFF:
        notename = midi2note(val1)
        print("%s ch:%d %s (%03d) vel:%d" %
              (msgtstr.ljust(7), ch, notename.ljust(3), val1, val2))
    else:
        print("%s ch:%d %03d, %03d" % (msgtstr, ch, val1, val2))


def _callback_mididump_with_src(str src, list msg, float t):
    msgt, ch = splitchannel(msg[0])
    msgtstr = msgtype2str(msgt)
    val1 = int(msg[1])
    val2 = int(msg[2])
    cdef str srcstr = src.ljust(20)[:20]
    if msgt == CC:
        print("%s | CC      ch:%02d  %03d -> %03d" % (srcstr, ch, val1, val2))
    elif msgt == NOTEON or msgt == NOTEOFF:
        notename = midi2note(val1)
        print("%s | %s ch:%d %s (%03d) vel:%d" %
              (srcstr, msgtstr.ljust(7), ch, notename.ljust(3), val1, val2))
    else:
        print("%s | %s ch:%d %03d, %03d" % (srcstr, msgtstr, ch, val1, val2))


def _callback_mididump_with_src_parsable(str src, list msg, float t):
    msgt, ch = splitchannel(msg[0])
    msgtstr = msgtype2str(msgt)
    val1 = int(msg[1])
    val2 = int(msg[2])
    vals = ", ".join(("%03d" % val for val in msg[1:]))
    print("%s, %f, %s, %02d, " % (src, t, msgtstr, ch) + vals)


def mididump(port_pattern="*", parsable=False, api=API_UNSPECIFIED):
    """
    Listen to all ports matching pattern and print the received messages

    Args:
        parsable: if True, it will return the data in comma delimited format
            source, timedelta, msgtype, channel, byte2, byte3[, ...]
        api: which api to use. In some platforms there is only one option
             (macOS, windows). 
    
    Returns:
        (MidiInMulti) The MidiInMulti created to listen to all midi inputs
    """
    m = MidiInMulti()
    m.open_ports(port_pattern)
    if not parsable:
        m._set_qualified_callback(_callback_mididump_with_src, src_as_string=True)
    else:
        m._set_qualified_callback(_callback_mididump_with_src_parsable, src_as_string=True)
    return m


def get_in_ports():
    """
    Returns a list of available in ports

    Returns:
        (list[str]) A list of available input ports, by name
    """
    return _get_midiin().ports


def get_out_ports():
    """
    Returns a list of available out ports

    Returns:
        (list[str]) A list of availabe output ports, by name
    """
    return MidiOut().ports

ctypedef vector[unsigned char] uchr_vec


cdef class MidiOut(MidiBase):
    cdef RtMidiOut* thisptr
    cdef bint virtual_port_opened
    
    def __cinit__(self, clientname=None, Api api=UNSPECIFIED):
        if clientname is None:
            self.thisptr = new RtMidiOut(api, string(<char*>"RTMIDI"))
        else:
            clientname = clientname.encode("ASCII", errors="ignore")
            self.thisptr = new RtMidiOut(api, string(<char*>clientname))
        self.virtual_port_opened = False
        self._openedports = []

    def __init__(self, clientname=None, api=API_UNSPECIFIED): pass

    def __dealloc__(self):
        self.close_port()
        del self.thisptr
       
    cdef RtMidi* baseptr(self):
        return self.thisptr

    def open_virtual_port(self, str port_name):
        if self.virtual_port_opened:
            raise IOError("Only one virtual port can be opened. If you need more, create a new MidiOut")
        self.virtual_port_opened = True
        return MidiBase.open_virtual_port(self, port_name)

    def send_raw(self, *bytes):
        cdef int lenbytes = len(bytes)
        cdef vector[unsigned char]v 
        v = uchr_vec(lenbytes)
        cdef unsigned char b
        cdef int i = 0
        for b in bytes:
            v[i] = b
            i += 1
        self.thisptr.sendMessage(&v)
        
    def send_sysex(self, *bytes):
        """
        Send a sysex message 

        Args:
            bytes: the content of the sysex message. 

        A sysex message consists of a starting byte 0xF0, the content of the sysex command,
        and an end byte 0xF7. The bytes need to be in the range 0-127
        """
        cdef int lenbytes = len(bytes)
        cdef vector[unsigned char]* v = new vector[unsigned char](lenbytes+2)
        cdef unsigned char b
        cdef int i = 1
        v[0][0] = 0xF0
        v[0][lenbytes+1] = 0xF7
        for b in bytes:
            v[0][i] = b
            i += 1
        self.thisptr.sendMessage(v)
        del v

    def send_pitchbend(self, unsigned char channel, unsigned int transp):
        """
        Send a pitchbend message

        Args:
            channel: 0-15
            pitch: 0 to 16383

        !!! note

            The 0 point (no transposition) is 8192

        The MIDI standard specifies a default of 2 semitones UP and 2 semitones DOWN for
        the pitch-wheel. To convert cents to pitchbend (cents between -200 and 200), use
        `cents2pitchbend`

        **See Also**: `pitchbend2cents`, `cents2pitchbend`
        """
        cdef unsigned char b1, b2
        if transp > 16383:
            return
        b1 = transp & 127
        b2 = transp >> 7
        self._send_raw3(DPITCHWHEEL+channel, b1, b2)

    cdef inline void _send_raw3(self, unsigned char b0, unsigned char b1, unsigned char b2):
        cdef uchr_vec msg_v
        msg_v = uchr_vec(3)
        msg_v[0] = b0
        msg_v[1] = b1
        msg_v[2] = b2
        self.thisptr.sendMessage(&msg_v)


    cpdef send_cc(self, unsigned char channel, unsigned char cc, unsigned char value):
        """
        Send a CC message

        Args:
            channel: 0-15
            cc: the CC index (0-127)
            value: the CC value (0-127)
        """
        self._send_raw3(DCC | channel, cc, value)

    cpdef send_messages(self, int messagetype, messages):
        """
        Args:
            messagetype: an integer identifying the kind of message
            messages: a list of tuples of the form `(channel, value1, value2)`


        | Message type | Value |
        | ------------ | ----- |
        | NOTEON       | 144   |
        | CC           | 176   |
        | NOTEOFF      | 128   |
        | PROGCHANGE   | 192   |
        | PITCHWHEEL   | 224   |

        
        Example
        -------

        ```python
        # send multiple noteoffs as noteon with velocity 0 for hosts which do not implement the noteoff message
        from rtmidi2 import *
        m = MidiOut()
        m.open_port()
        messages = [(0, i, 0) for i in range(127)]
        m.send_messages(144, messages)
        ```
        """
        cdef uchr_vec m
        m = uchr_vec(3)
        m.push_back(0)
        m.push_back(0)
        m.push_back(0)
        cdef tuple tuprow
        if isinstance(messages, list):
            for tuprow in <list>messages:
                m = tuprow
                self.thisptr.sendMessage(&m)
        else:
            raise TypeError("messages should be a list of tuples. other containers are not supported")
        return None

    cpdef send_noteon(self, unsigned char channel, unsigned char midinote, unsigned char velocity):
        """
        Send a NOTEON message

        Args:
            channel: 0-15
            midinote: a midinote (0-127)
            velocity: velocity (0-127)
        """
        self._send_raw3(DNOTEON|channel, midinote, velocity)

    def send_noteon_many(self, channel not None, notes not None, vels not None):
        """
        Send many noteon messages at once

        Args:
            channel: an integer indicating the midi channel, or a list of channels
                (must be the same length as notes)
            notes: a list of midinotes
            vels: a list of velocities

        """
        cdef vector[unsigned char]* m = new vector[unsigned char](3)
        if not isinstance(notes, list):
            del m
            raise NotImplemented("notes and vels should be lists. other containers are not yet implemented")
        if isinstance(channel, list) and isinstance(notes, list) and isinstance(vels, list):
            for i in range(len(<list>notes)):
                m[0][0] = DNOTEON |<unsigned char>(<list>channel)[i]
                m[0][1] = <unsigned char>(<list>notes)[i]
                m[0][2] = <unsigned char>(<list>vels)[i]
                self.thisptr.sendMessage(m)
        else:
            if isinstance(channel, int):
                m[0][0] = channel
                for i in range(len(notes)):
                    m[0][1] = <unsigned char>(notes[i])
                    m[0][2] = <unsigned char>(vels[i])
                    self.thisptr.sendMessage(m)
            else:
                for i in range(len(notes)):
                    m[0][0] = <unsigned char>(channel[i])
                    m[0][1] = <unsigned char>(notes[i])
                    m[0][2] = <unsigned char>(vels[i])
                    self.thisptr.sendMessage(m)
        del m

    cpdef send_noteoff(self, unsigned char channel, unsigned char midinote):
        """
        Send a noteoff message

        Args:
            channel: 0-15
            midinote: the midinote to stop
        """
        self._send_raw3(DNOTEOFF|channel, midinote, 0)

    cpdef send_noteoff_many(self, channels, notes):
        """
        Send many noteoff messages at once

        Args:
            channels: a list of channels, or a single integer channel
            notes: a list of midinotes to be released

        !!! note

            A channel has a value between 0-15
        """
        cdef channel, v0
        cdef vector[unsigned char]* m = new vector[unsigned char](3)
        m[0][2] = 0
        if isinstance(channels, int):
            v0 = DNOTEOFF | <unsigned char>channels
            if isinstance(notes, list):
                for i in range(len(<list>notes)):
                    m[0][0] = v0
                    m[0][1] = <unsigned char>(<list>notes)[i]
                    self.thisptr.sendMessage(m)
            else:
                del m
                raise NotImplemented("only lists implemented right now")
        elif isinstance(channels, list):
            for i in range(len(<list>notes)):
                m[0][0] = DNOTEOFF | <unsigned char>(<list>channels)[i]
                m[0][1] = <unsigned char>(<list>notes)[i]
                self.thisptr.sendMessage(m)
        del m
        return None

    def get_current_api(self):
        """
        Return the low-level MIDI backend API used by this instance.
        Use this by comparing the returned value to the module-level ``API_*``
        constants

        Example
        ------- 

        ```python
        from rtmidi2 import *
        midiout = rtmidi.MidiOut()
        if midiout.get_current_api() == rtmidi.API_UNIX_JACK:
            print("Using JACK API for MIDI output.")
        ```
        """
        return self.thisptr.getCurrentApi()


cpdef int cents2pitchbend(int cents, int maxdeviation=200):
    """
    Convert cents to a pitchbend value

    Args:
        cents: an integer between -maxdeviation and +maxdviation

    Returns:
        (int) The pitchbend value corresponding to the given cents
    """
    return int((cents+maxdeviation)/(maxdeviation*2.0) * 16383.0 + 0.5)


cpdef int pitchbend2cents(int pitchbend, maxcents=200):
    """
    Convert a pitchbend value to cents

    Args:
        pitchbend: an integer between 0 and 16383
        maxcents: the max. cents deviation 

    Returns:
        (int) The cents corresponding to the given pitchbend
    """
    return int(((pitchbend/16383.0)*(maxcents*2.0))-maxcents+0.5)


cpdef MidiIn _get_midiin():
    return MidiIn("inspector")
    
