=======
rtmidi2
=======

Python wrapper for RtMidi_, the lightweight, cross-platform MIDI I/O library. For Linux, Mac OS X and Windows.

Based on rtmidi-python

Installation
------------

    pip install rtmidi2

    
This module is compatible with Python 3 >= 3.7 

Usage Examples
--------------

`rtmidi2` uses a very similar API as RtMidi

Print all in and out ports
~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: python

   import rtmidi2
   print(rtmidi2.get_in_ports())
   print(rtmidi2.get_out_ports())


Send messages
~~~~~~~~~~~~~

.. code-block:: python

   import rtmidi2
  
   midi_out = rtmidi2.MidiOut()
   # open the first available port
   midi_out.open_port(0) 
   # send C3 with vel. 100 on channel 1
   midi_out.send_noteon(0, 48, 100)



Get incoming messages - blocking interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: python

   midi_in = rtmidi.MidiIn()
   midi_in.open_port(0)

   while True:
       message, delta_time = midi_in.get_message()  # will block until a message is available
       if message:
            print(message, delta_time)


Get incoming messages using a callback -- non blocking
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: python

    def callback(message, time_stamp):
        print(message, time_stamp)

    midi_in = rtmidi2.MidiIn()
    midi_in.callback = callback
    midi_in.open_port(0)


Open multiple ports at once
~~~~~~~~~~~~~~~~~~~~~~~~~~~
   
.. code-block:: python

    # get messages from all available ports
    midi_in = MidiInMulti().open_ports("*")

    def callback(msg, timestamp):
        msgtype, channel = splitchannel(msg[0])
        print(msgtype2str(msgtype), msg[1], msg[2])

    midi_in.callback = callback


You can also get the device which generated the event by changing your callback to:

.. code-block:: python

    def callback(src, msg, timestamp):
        # src will hold the name of the device
        print("got message from", src)

               
Send multiple notes at once
~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: python

    # send a cluster of ALL notes with a duration of 1 second
    midi_out = MidiOut().open_port()
    notes = range(127)
    velocities = [90] * len(notes)
    midi_out.send_noteon_many(0, notes, velocities)
    time.sleep(1)
    midi_out.send_noteon_many(0, notes, [0] * len(notes))


----


License
-------

`rtmidi2` is licensed under the MIT License, see `LICENSE`.

It uses RtMidi, licensed under a modified MIT License, see `RtMidi/RtMidi.h`.


.. _RtMidi: http://www.music.mcgill.ca/~gary/rtmidi/
.. _Cython: http://www.cython.org
