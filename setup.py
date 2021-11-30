import sys
from setuptools import setup, Extension

version = "0.9.3"  

module_source = 'rtmidi2.pyx'

long_description = open("README.rst").read()

extension_args = {}

if sys.platform.startswith('linux'):
    extension_args = dict(
        define_macros=[
            ('__LINUX_ALSASEQ__', None),
            ('__LINUX_ALSA__', None),
            ('__UNIX_JACK__', None)
        ],
        libraries=['asound', 'pthread', 'jack']
    )

if sys.platform == 'darwin':
    extension_args = dict(
        define_macros=[('__MACOSX_CORE__', None)],
        extra_compile_args=['-frtti'],
        extra_link_args=[
            '-framework', 'CoreMidi',
            '-framework', 'CoreAudio',
            '-framework', 'CoreFoundation'
        ]
    )

if sys.platform == 'win32':
    extension_args = dict(
        define_macros=[('__WINDOWS_MM__', None)],
        libraries=['winmm']
    )

setup(
    name='rtmidi2',
    python_requires='>=3.8',
    version=version,
    ext_modules=[
        Extension(
            'rtmidi2',
            sources = ['rtmidi2.pyx', 'RtMidi/RtMidi.cpp'],
            include_dirs = ["RtMidi"],
            depends = ['RtMidi/RtMidi.hpp'],
            language='c++',
            **extension_args
        )
    ],
    setup_requires=['cython'],
    license='MIT',
    platforms='any',
    classifiers=[
        'Development Status :: 4 - Beta',
        'Programming Language :: Cython',
        'Topic :: Multimedia :: Sound/Audio :: MIDI',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Topic :: Software Development :: Libraries :: Python Modules'
    ],
    description='Python wrapper for RtMidi written in Cython. Allows sending raw messages, multi-port input and sending multiple messages in one call.',
    long_description=long_description,
    author='originally by Guido Lorenz, modified by Eduardo Moguillansky',
    author_email='eduardo.moguillansky@gmail.com',
    url="https://github.com/gesellkammer/rtmidi2",        
)
