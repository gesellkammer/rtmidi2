# cython: binding=True
# cython: boundscheck=False
# cython: embedsignature=True
# cython: checknone=False
# cython: language_level=3

### cython imports
from libcpp.string cimport string
from libcpp.vector cimport vector
from cython.operator cimport dereference as deref, preincrement as inc

import inspect
import fnmatch

# NOTE: PyEval_InitThreads() was removed here. It has been a no-op since
# Python 3.7 (threads/GIL are initialized automatically) and was removed
# from the C API in Python 3.13. RtMidi callbacks below are declared
# `with gil`, so Python callbacks from native threads remain safe.

### constants
# DEF DNOTEON     = 144
# DEF DCC         = 176
# DEF DNOTEOFF    = 128
# DEF DPROGCHANGE = 192
# DEF DPITCHWHEEL = 224
# DEF QUEUESIZE   = 1024

QUEUESIZE  = 1024
NOTEON     = 144
CC         = 176
NOTEOFF    = 128
PROGCHANGE = 192
PITCHWHEEL = 224

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
        WEB_MIDI_API "RtMidi::WEB_MIDI_API"
        WINDOWS_UWP  "RtMidi::WINDOWS_UWP"
        ANDROID_AMIDI "RtMidi::ANDROID_AMIDI"

API_UNSPECIFIED = UNSPECIFIED
API_MACOSX_CORE = MACOSX_CORE
API_LINUX_ALSA = LINUX_ALSA
API_UNIX_JACK = UNIX_JACK
API_WINDOWS_MM = WINDOWS_MM
API_RTMIDI_DUMMY = RTMIDI_DUMMY
API_WINDOWS_UWP = WINDOWS_UWP
API_ANDROID_AMIDI = ANDROID_AMIDI
API_WEB_MIDI_API = WEB_MIDI_API

### C++ interface
cdef extern from "RtMidi/RtMidi.h":
    ctypedef void (*RtMidiCallback)(double timeStamp, vector[unsigned char]* message, void* userData) except * with gil

    cdef cppclass RtMidi:
        void openPort(unsigned int portNumber) except *
        void openVirtualPort(string portName) except *
        unsigned int getPortCount() except *
        string getPortName(unsigned int portNumber) except *
        void closePort() except *

    cdef cppclass RtMidiIn(RtMidi):
        RtMidiIn(RtMidi.Api api, string clientName, unsigned int queueSizeLimit) except+
        void setCallback(RtMidiCallback callback, void* userData) except+
        void cancelCallback() except+
        void ignoreTypes(bint midiSysex, bint midiTime, bint midiSense)
        double getMessage(vector[unsigned char]* message) except+
        Api getCurrentApi()

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
        cdef list _ports = self.ports
        cdef int port_number
        if isinstance(port, int):
            if port < 0 or port >= len(_ports):
                raise ValueError("port number out of range")
            port_number = port
        elif isinstance(port, str):
            if port in _ports:
                port_number = _ports.index(port)
            else:
                match = self.ports_matching(port)
                if match:
                    return self.open_port(match[0])
                else:
                    raise ValueError("Port not found")
        else:
            raise TypeError("port must be an int index or str name/pattern")
        self.baseptr().openPort(<unsigned int>port_number)
        if self._openedports is None:
            self._openedports = []
        if port_number not in self._openedports:
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
        cdef bytes bport = port_name.encode('utf-8', errors='ignore')
        self.baseptr().openVirtualPort(string(<char*>bport, len(bport)))
        if self._openedports is None:
            self._openedports = []
        if port_name not in self._openedports:
            self._openedports.append(port_name)

    def close_port(self):
        """
        Close an open port
        """
        self.baseptr().closePort()
        # Single-port objects only track what was opened; reset on close
        # so _openedports does not go stale after close/failure.
        self._openedports = []

    def get_current_api(self):
        """
        Return the low-level MIDI backend API used by this instance.
        Compare against the module-level ``API_*`` constants.
        """
        raise NotImplementedError("implemented in MidiIn/MidiOut")

    def ports_matching(self, pattern):
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
        if pattern is None:
            raise TypeError("pattern must be a str, not None")
        if not isinstance(pattern, str):
            raise TypeError("pattern must be a str")
        ports = self.ports
        return [i for i, port in enumerate(ports)
                if port is not None and fnmatch.fnmatch(port, pattern)]


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

    def __cinit__(self, clientname=None, queuesize=QUEUESIZE, Api api=UNSPECIFIED):
        cdef bytes bname
        if queuesize < 0:
            raise ValueError("queuesize must be >= 0")
        cdef unsigned int qsize = <unsigned int>queuesize
        if clientname is None:
            self.thisptr = new RtMidiIn(api, string(<char*>"RTMIDI", 6), qsize)
        else:
            if not isinstance(clientname, str):
                raise TypeError("clientname must be a str or None")
            bname = clientname.encode("utf-8", errors="ignore")
            self.thisptr = new RtMidiIn(api, string(<char*>bname, len(bname)), qsize)
        self.py_callback = None
        self._openedports = []

    def __dealloc__(self):
        # Cancel callback first: otherwise the native RtMidi thread may
        # invoke midi_in_callback with a dangling void* after free.
        # (Only cancel when one was set: RtMidi warns on stray cancel.)
        if self.thisptr is not NULL:
            if self.py_callback is not None:
                try:
                    self.thisptr.cancelCallback()
                except Exception:
                    pass
            try:
                self.thisptr.closePort()
            except Exception:
                pass
            del self.thisptr
            self.thisptr = NULL
        self.py_callback = None

    cdef RtMidi* baseptr(self):
        return self.thisptr

    def get_current_api(self):
        return self.thisptr.getCurrentApi()

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
        Get a midi message

        This call will return immediately, returning a list of ints, each
        in the range 0-255 representing the chars in the message, or None
        if the queue was empty

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
        # cdef vector[unsigned char]* message_vector = new vector[unsigned char]()
        cdef vector[unsigned char] message_vector
        cdef double deltatime = self.thisptr.getMessage(&message_vector)
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
    cdef unsigned int queuesize
    cdef Api api
    cdef readonly object clientname
    cdef object py_callback
    cdef list qualified_callbacks
    cdef readonly list _openedports
    cdef dict hascallback
    cdef bint _qualified_mode
    cdef bint _src_as_string
    cdef object _inspector_cache

    cdef MidiIn _inspector(self):
        # Cache the inspector: each MidiIn() constructs a native
        # RtMidi client, so creating one per property access is wasteful.
        if self._inspector_cache is None:
            self._inspector_cache = MidiIn("INSPECTOR", self.queuesize, self.api)
        return <MidiIn>self._inspector_cache

    property inspector:
        def __get__(self):
            return self._inspector()

    def __cinit__(self, clientname=None, queuesize=QUEUESIZE, Api api=UNSPECIFIED):
        self.ptrs = new vector[RtMidiIn *]()
        self.py_callback = None
        self.qualified_callbacks = []
        self.api = api
        if queuesize < 0:
            raise ValueError("queuesize must be >= 0")
        self.queuesize = <unsigned int>queuesize
        self._qualified_mode = False
        self._src_as_string = True
        self._inspector_cache = None

    def __init__(self, clientname=None, queuesize=QUEUESIZE, Api api=UNSPECIFIED):
        if queuesize < 0:
            raise ValueError("queuesize must be >= 0")
        self.queuesize = <unsigned int>queuesize
        self.api = api
        self._openedports = []
        self.hascallback = {}
        if clientname is None:
            clientname = "RTMIDI"
        if not isinstance(clientname, str):
            raise TypeError("clientname must be a str or None")
        self.clientname = clientname.encode("utf-8", errors="ignore")

    def __dealloc__(self):
        if self.ptrs is not NULL:
            try:
                self.close_ports()
            except Exception:
                pass
            del self.ptrs
            self.ptrs = NULL
        self.py_callback = None
        self.qualified_callbacks = []
        self._inspector_cache = None

    def __repr__(self):
        try:
            allports = self.ports
            names = []
            for port in self._openedports:
                try:
                    names.append(allports[port])
                except Exception:
                    names.append("<port %s>" % (port,))
            s = " + ".join(n for n in names if n is not None)
        except Exception:
            s = ",".join(str(p) for p in self._openedports)
        return "MidiInMulti ( %s )" % s

    property ports:
        def __get__(self):
            return self._inspector().ports

    def get_open_ports(self):
        """
        Returns a list of the open ports, by index
        To get the name, use .get_port_name

        Returns:
            a list with the indexes of the open ports
        """
        return list(self._openedports)

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
        return self._inspector().get_port_name(portindex, encoding)

    def get_callback(self):
        """Returns the python callback of this MidiIn"""
        return self.py_callback

    def get_current_api(self):
        """
        Return the low-level MIDI backend API used by the open ports.
        Compare against the module-level ``API_*`` constants.
        Raises RuntimeError if no port is open.
        """
        if self.ptrs.empty():
            raise RuntimeError("no port open")
        cdef RtMidiIn* first = self.ptrs.at(0)
        return first.getCurrentApi()

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
        if pattern is None:
            raise TypeError("pattern must be a str, not None")
        if not isinstance(pattern, str):
            raise TypeError("pattern must be a str")
        if exclude is not None and not isinstance(exclude, str):
            raise TypeError("exclude must be a str or None")
        ports = self.ports
        if exclude is None:
            return [i for i, port in enumerate(ports)
                    if port is not None and fnmatch.fnmatch(port, pattern)]
        else:
            return [i for i, port in enumerate(ports)
                    if port is not None and fnmatch.fnmatch(port, pattern)
                    and not fnmatch.fnmatch(port, exclude)]

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
        if port >= len(self._inspector().ports):
            raise ValueError("Port out of range")
        if port in self._openedports:
            raise ValueError("Port already open!")
        cdef bytes cname = <bytes>self.clientname
        cdef RtMidiIn* newport = new RtMidiIn(self.api, string(<char*>cname, len(cname)), self.queuesize)
        try:
            newport.openPort(port)
        except Exception:
            del newport
            raise
        self.ptrs.push_back(newport)
        self._openedports.append(port)
        # a new open port should be assigned the current callback, if any,
        # preserving qualified mode and src_as_string.
        if self.py_callback is not None:
            self._apply_callback_to_port(self.ptrs.size() - 1)
        
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
        cdef Py_ssize_t n = self.ptrs.size()
        for i in range(n):
            ptr = self.ptrs.at(i)
            if ptr is not NULL:
                try:
                    port = self._openedports[i]
                    if self.hascallback.get(port, False):
                        ptr.cancelCallback()
                except Exception:
                    pass
                try:
                    ptr.closePort()
                except Exception:
                    pass
                del ptr
        self.hascallback = {}
        self.ptrs.clear()
        self._openedports = []
        self.qualified_callbacks = []
        self.py_callback = None
        self._qualified_mode = False
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
        try:
            if self.hascallback.get(port, False):
                ptr.cancelCallback()
        except Exception:
            pass
        try:
            ptr.closePort()
        except Exception:
            pass
        del ptr
        self.ptrs.erase(self.ptrs.begin()+port_index)
        self._openedports.pop(port_index)
        self.hascallback.pop(port, None)
        # Drop stale qualified (src, cb) tuples for the closed port.
        # Tuples are (src, callback); src may be port int or port-name str.
        try:
            portname = self._inspector().get_port_name(port)
        except Exception:
            portname = None
        self.qualified_callbacks = [
            tup for tup in self.qualified_callbacks
            if not (isinstance(tup, tuple) and len(tup) == 2
                    and (tup[0] == port or (portname is not None and tup[0] == portname)))
        ]
        if self.ptrs.empty():
            self.py_callback = None
            self._qualified_mode = False
        return 1

    property callback:
        def __get__(self):
            return self.py_callback
        def __set__(self, callback):
            cdef RtMidiIn* ptr
            if callback is None:
                self._cancel_callbacks()
                return
            if not callable(callback):
                raise TypeError("callback must be callable or None")
            numargs = _func_get_numargs(callback)
            if numargs == 3:
                self._set_qualified_callback(callback, True)
                return
            if not (numargs == 2 or numargs is None):
                raise TypeError("callback should be a callable function of the form func(msg, time) or func(src, msg, time)")
            self.py_callback = callback
            self._qualified_mode = False
            self._src_as_string = True
            self.qualified_callbacks = []
            for i in range(self.ptrs.size()):
                ptr = self.ptrs.at(i)
                port = self._openedports[i]
                if self.hascallback.get(port, False):
                    ptr.cancelCallback()
                ptr.setCallback(midi_in_callback, <void*>callback)
                self.hascallback[port] = True

    cdef void _apply_callback_to_port(self, Py_ssize_t idx):
        """Install the current callback on a newly opened port."""
        cdef RtMidiIn* ptr = self.ptrs.at(idx)
        port = self._openedports[idx]
        if self._qualified_mode:
            if self._src_as_string:
                tup = (self.get_port_name(port), self.py_callback)
            else:
                tup = (port, self.py_callback)
            self.qualified_callbacks.append(tup)
            ptr.setCallback(midi_in_callback_with_src, <void*>tup)
        else:
            ptr.setCallback(midi_in_callback, <void*>self.py_callback)
        self.hascallback[port] = True

    def _cancel_callbacks(self):
        cdef RtMidiIn* ptr
        for i in range(self.ptrs.size()):
            ptr = self.ptrs.at(i)
            port = self._openedports[i]
            if self.hascallback.get(port, False):
                try:
                    ptr.cancelCallback()
                except Exception:
                    pass
                self.hascallback[port] = False
        self.py_callback = None
        self.qualified_callbacks = []
        self._qualified_mode = False
        self._src_as_string = True

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
        if callback is None:
            self._cancel_callbacks()
            return
        if not callable(callback):
            raise TypeError("callback must be callable or None")
        numargs = _func_get_numargs(callback)
        if numargs == 2 or numargs is None:
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
        if callback is not None and not callable(callback):
            raise TypeError("callback must be callable or None")
        self.py_callback = callback
        self._qualified_mode = True
        self._src_as_string = bool(src_as_string)
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
        raise NotImplementedError("The blocking interface is not implemented for multiple "
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
    """Return 2 or 3 for func(msg, time) / func(src, msg, time), else None if unknown.

    Note: inspect.signature() already excludes self/cls for bound methods,
    so no manual trimming is needed (and trimming would corrupt callables
    whose first *remaining* parameter happens to be named self/cls).
    """
    try:
        params = list(inspect.signature(func).parameters.values())
    except (TypeError, ValueError):
        return None
    kinds = {inspect.Parameter.VAR_POSITIONAL, inspect.Parameter.VAR_KEYWORD}
    if any(p.kind in kinds for p in params):
        # *args/**kwargs: arity unknown, caller treats as generic 2-arg
        return None
    poskinds = {inspect.Parameter.POSITIONAL_ONLY,
                inspect.Parameter.POSITIONAL_OR_KEYWORD}
    n_positional = sum(1 for p in params if p.kind in poskinds)
    if n_positional in (2, 3):
        # Covers both exact signatures and ones with defaults,
        # e.g. def cb(msg, t=0.0) counts as 2-arg
        return n_positional
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
    if midinote < 0 or midinote > 127:
        raise ValueError("midinote must be in range 0-127")
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
    if not msg:
        print("<empty message>")
        return
    msgt, ch = splitchannel(msg[0])
    msgtstr = msgtype2str(msgt)
    val1 = int(msg[1]) if len(msg) > 1 else -1
    val2 = int(msg[2]) if len(msg) > 2 else -1
    if msgt == CC and len(msg) >= 3:
        print("CC      ch:%02d  %03d -> %03d" % (ch, val1, val2))
    elif (msgt == NOTEON or msgt == NOTEOFF) and len(msg) >= 3:
        notename = midi2note(val1)
        print("%s ch:%d %s (%03d) vel:%d" %
              (msgtstr.ljust(7), ch, notename.ljust(3), val1, val2))
    else:
        rest = ", ".join("%03d" % int(v) for v in msg[1:]) if len(msg) > 1 else ""
        print("%s ch:%d %s" % (msgtstr, ch, rest))


def _callback_mididump_with_src(src, list msg, float t):
    if not msg:
        print("%s | <empty message>" % (src,))
        return
    msgt, ch = splitchannel(msg[0])
    msgtstr = msgtype2str(msgt)
    val1 = int(msg[1]) if len(msg) > 1 else -1
    val2 = int(msg[2]) if len(msg) > 2 else -1
    cdef str srcstr = str(src).ljust(20)[:20]
    if msgt == CC and len(msg) >= 3:
        print("%s | CC      ch:%02d  %03d -> %03d" % (srcstr, ch, val1, val2))
    elif (msgt == NOTEON or msgt == NOTEOFF) and len(msg) >= 3:
        notename = midi2note(val1)
        print("%s | %s ch:%d %s (%03d) vel:%d" %
              (srcstr, msgtstr.ljust(7), ch, notename.ljust(3), val1, val2))
    else:
        rest = ", ".join("%03d" % int(v) for v in msg[1:]) if len(msg) > 1 else ""
        print("%s | %s ch:%d %s" % (srcstr, msgtstr, ch, rest))


def _callback_mididump_with_src_parsable(src, list msg, float t):
    if not msg:
        print("%s, %f, <empty>" % (src, t))
        return
    msgt, ch = splitchannel(msg[0])
    msgtstr = msgtype2str(msgt)
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
    m = MidiInMulti(api=api)
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
        cdef bytes bname
        if clientname is None:
            self.thisptr = new RtMidiOut(api, string(<char*>"RTMIDI", 6))
        else:
            if not isinstance(clientname, str):
                raise TypeError("clientname must be a str or None")
            bname = clientname.encode("utf-8", errors="ignore")
            self.thisptr = new RtMidiOut(api, string(<char*>bname, len(bname)))
        self.virtual_port_opened = False
        self._openedports = []

    def __init__(self, clientname=None, api=API_UNSPECIFIED): pass

    def __dealloc__(self):
        if self.thisptr is not NULL:
            try:
                self.thisptr.closePort()
            except Exception:
                pass
            del self.thisptr
            self.thisptr = NULL

    cdef RtMidi* baseptr(self):
        return self.thisptr

    def get_current_api(self):
        """
        Return the low-level MIDI backend API used by this instance.
        Use this by comparing the returned value to the module-level ``API_*``
        constants

        Example
        -------

        ```python
        from rtmidi2 import *
        midiout = MidiOut()
        if midiout.get_current_api() == API_UNIX_JACK:
            print("Using JACK API for MIDI output.")
        ```
        """
        return self.thisptr.getCurrentApi()

    def open_virtual_port(self, str port_name):
        if self.virtual_port_opened:
            raise IOError("Only one virtual port can be opened. If you need more, create a new MidiOut")
        MidiBase.open_virtual_port(self, port_name)
        self.virtual_port_opened = True

    def close_port(self):
        MidiBase.close_port(self)
        self.virtual_port_opened = False

    def send_raw(self, *bytes):
        cdef Py_ssize_t i, n = len(bytes)
        cdef long v
        for i in range(n):
            v = <long>bytes[i]
            if v < 0 or v > 255:
                raise ValueError("MIDI bytes must be in range 0-255")
        cdef vector[unsigned char] msg = uchr_vec(n)
        for i in range(n):
            msg[<size_t>i] = <unsigned char>(<long>bytes[i])
        self.thisptr.sendMessage(&msg)

    def send_message(self, msg):
        """
        Send a MIDI message given as a list/tuple of ints (0-255).

        This is an alias kept for compatibility; ``send_raw(*msg)`` is
        equivalent.
        """
        if not isinstance(msg, (list, tuple)):
            raise TypeError("msg must be a list or tuple of ints")
        self.send_raw(*msg)

    def send_sysex(self, *bytes):
        """
        Send a sysex message

        Args:
            bytes: the content of the sysex message.

        A sysex message consists of a starting byte 0xF0, the content of the sysex command,
        and an end byte 0xF7. The bytes need to be in the range 0-127
        """
        cdef Py_ssize_t n = len(bytes)
        cdef long v
        for v in bytes:
            if v < 0 or v > 127:
                raise ValueError("sysex data bytes must be in range 0-127")
        cdef vector[unsigned char] msg = uchr_vec(n + 2)
        msg[<size_t>0] = 0xF0
        cdef Py_ssize_t i
        for i in range(n):
            msg[<size_t>(i + 1)] = <unsigned char>(<long>bytes[i])
        msg[<size_t>(n + 1)] = 0xF7
        self.thisptr.sendMessage(&msg)

    def send_pitchbend(self, channel, transp):
        """
        Send a pitchbend message

        Args:
            channel: 0-15
            transp: 0 to 16383

        !!! note

            The 0 point (no transposition) is 8192

        The MIDI standard specifies a default of 2 semitones UP and 2 semitones DOWN for
        the pitch-wheel. To convert cents to pitchbend (cents between -200 and 200), use
        `cents2pitchbend`

        **See Also**: `pitchbend2cents`, `cents2pitchbend`
        """
        cdef long ch = <long>channel
        cdef long pb = <long>transp
        if ch < 0 or ch > 15:
            raise ValueError("channel must be in range 0-15")
        if pb < 0 or pb > 16383:
            raise ValueError("pitchbend value must be in range 0-16383")
        cdef unsigned char b1 = <unsigned char>(pb & 127)
        cdef unsigned char b2 = <unsigned char>((pb >> 7) & 127)
        self._send_raw3(<unsigned char>(224 | ch), b1, b2)

    cdef inline void _send_raw3(self, unsigned char b0, unsigned char b1, unsigned char b2):
        cdef uchr_vec msg_v
        msg_v = uchr_vec(3)
        msg_v[0] = b0
        msg_v[1] = b1
        msg_v[2] = b2
        self.thisptr.sendMessage(&msg_v)


    cpdef send_cc(self, channel, cc, value):
        """
        Send a CC message

        Args:
            channel: 0-15
            cc: the CC index (0-127)
            value: the CC value (0-127)
        """
        cdef long ch = <long>channel
        cdef long c = <long>cc
        cdef long v = <long>value
        if ch < 0 or ch > 15:
            raise ValueError("channel must be in range 0-15")
        if c < 0 or c > 127:
            raise ValueError("cc must be in range 0-127")
        if v < 0 or v > 127:
            raise ValueError("value must be in range 0-127")
        self._send_raw3(<unsigned char>(176 | ch), <unsigned char>c, <unsigned char>v)

    cpdef send_messages(self, int messagetype, messages):
        """
        Args:
            messagetype: an integer identifying the kind of message
            messages: a sequence of tuples of the form `(channel, value1, value2)`


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
        if messagetype not in (NOTEON, NOTEOFF, CC, PROGCHANGE, PITCHWHEEL):
            raise ValueError("unsupported messagetype")
        if not isinstance(messages, (list, tuple, range)):
            raise TypeError("messages should be a list/tuple of (channel, value1, value2) tuples")
        cdef vector[unsigned char] m = uchr_vec(3)
        cdef long ch, v1, v2
        for row in messages:
            if not isinstance(row, (list, tuple)) or len(row) != 3:
                raise ValueError("each message must be a (channel, value1, value2) triple")
            ch, v1, v2 = <long>row[0], <long>row[1], <long>row[2]
            if ch < 0 or ch > 15:
                raise ValueError("channel must be in range 0-15")
            if v1 < 0 or v1 > 127 or v2 < 0 or v2 > 127:
                raise ValueError("MIDI data bytes must be in range 0-127")
            m[<size_t>0] = <unsigned char>(messagetype | ch)
            m[<size_t>1] = <unsigned char>v1
            m[<size_t>2] = <unsigned char>v2
            self.thisptr.sendMessage(&m)
        return None

    cpdef send_noteon(self, channel, midinote, velocity):
        """
        Send a NOTEON message

        Args:
            channel: 0-15
            midinote: a midinote (0-127)
            velocity: velocity (0-127)
        """
        cdef long ch = <long>channel
        cdef long note = <long>midinote
        cdef long vel = <long>velocity
        if ch < 0 or ch > 15:
            raise ValueError("channel must be in range 0-15")
        if note < 0 or note > 127:
            raise ValueError("midinote must be in range 0-127")
        if vel < 0 or vel > 127:
            raise ValueError("velocity must be in range 0-127")
        self._send_raw3(<unsigned char>(144 | ch), <unsigned char>note, <unsigned char>vel)

    def send_noteon_many(self, channel not None, notes not None, vels not None):
        """
        Send many noteon messages at once

        Args:
            channel: an integer indicating the midi channel, or a sequence of channels
                (must be the same length as notes)
            notes: a sequence of midinotes
            vels: a sequence of velocities

        """
        if not isinstance(notes, (list, tuple, range)):
            raise TypeError("notes should be a list, tuple or range")
        if not isinstance(vels, (list, tuple, range)):
            raise TypeError("vels should be a list, tuple or range")
        if len(notes) != len(vels):
            raise ValueError("notes and vels must have the same length")
        cdef vector[unsigned char] m = uchr_vec(3)
        cdef Py_ssize_t i, n = len(notes)
        cdef long ch, note, vel
        if isinstance(channel, int):
            ch = <long>channel
            if ch < 0 or ch > 15:
                raise ValueError("channel must be in range 0-15")
            m[<size_t>0] = <unsigned char>(144 | ch)
            for i in range(n):
                note, vel = <long>notes[i], <long>vels[i]
                if note < 0 or note > 127 or vel < 0 or vel > 127:
                    raise ValueError("notes/vels must be in range 0-127")
                m[<size_t>1] = <unsigned char>note
                m[<size_t>2] = <unsigned char>vel
                self.thisptr.sendMessage(&m)
        elif isinstance(channel, (list, tuple, range)):
            if len(channel) != n:
                raise ValueError("channel sequence must match notes length")
            for i in range(n):
                ch, note, vel = <long>channel[i], <long>notes[i], <long>vels[i]
                if ch < 0 or ch > 15:
                    raise ValueError("channel must be in range 0-15")
                if note < 0 or note > 127 or vel < 0 or vel > 127:
                    raise ValueError("notes/vels must be in range 0-127")
                m[<size_t>0] = <unsigned char>(144 | ch)
                m[<size_t>1] = <unsigned char>note
                m[<size_t>2] = <unsigned char>vel
                self.thisptr.sendMessage(&m)
        else:
            raise TypeError("channel must be an int or a list/tuple of ints")

    cpdef send_noteoff(self, channel, midinote):
        """
        Send a noteoff message

        Args:
            channel: 0-15
            midinote: the midinote to stop
        """
        cdef long ch = <long>channel
        cdef long note = <long>midinote
        if ch < 0 or ch > 15:
            raise ValueError("channel must be in range 0-15")
        if note < 0 or note > 127:
            raise ValueError("midinote must be in range 0-127")
        # 128 = NOTEOFF
        self._send_raw3(<unsigned char>(128 | ch), <unsigned char>note, 0)

    cpdef send_noteoff_many(self, channels, notes):
        """
        Send many noteoff messages at once

        Args:
            channels: a sequence of channels, or a single integer channel
            notes: a sequence of midinotes to be released

        !!! note

            A channel has a value between 0-15
        """
        if not isinstance(notes, (list, tuple, range)):
            raise TypeError("notes should be a list, tuple or range")
        cdef vector[unsigned char] m = uchr_vec(3)
        m[<size_t>2] = 0
        cdef Py_ssize_t i, n = len(notes)
        cdef long ch, note
        if isinstance(channels, int):
            ch = <long>channels
            if ch < 0 or ch > 15:
                raise ValueError("channel must be in range 0-15")
            m[<size_t>0] = <unsigned char>(128 | ch)
            for i in range(n):
                note = <long>notes[i]
                if note < 0 or note > 127:
                    raise ValueError("notes must be in range 0-127")
                m[<size_t>1] = <unsigned char>note
                self.thisptr.sendMessage(&m)
        elif isinstance(channels, (list, tuple, range)):
            if len(channels) != n:
                raise ValueError("channels and notes must have the same length")
            for i in range(n):
                ch, note = <long>channels[i], <long>notes[i]
                if ch < 0 or ch > 15:
                    raise ValueError("channel must be in range 0-15")
                if note < 0 or note > 127:
                    raise ValueError("notes must be in range 0-127")
                m[<size_t>0] = <unsigned char>(128 | ch)
                m[<size_t>1] = <unsigned char>note
                self.thisptr.sendMessage(&m)
        else:
            raise TypeError("channels must be an int or a list/tuple of ints")
        return None


cpdef int cents2pitchbend(int cents, int maxdeviation=200):
    """
    Convert cents to a pitchbend value

    Args:
        cents: an integer between -maxdeviation and +maxdviation

    Returns:
        (int) The pitchbend value corresponding to the given cents
    """
    if maxdeviation <= 0:
        raise ValueError("maxdeviation must be > 0")
    if cents < -maxdeviation or cents > maxdeviation:
        raise ValueError("cents out of range")
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
    if pitchbend < 0 or pitchbend > 16383:
        raise ValueError("pitchbend must be in range 0-16383")
    if maxcents <= 0:
        raise ValueError("maxcents must be > 0")
    return int(((pitchbend/16383.0)*(maxcents*2.0))-maxcents+0.5)


cpdef MidiIn _get_midiin():
    return MidiIn("inspector")
    
