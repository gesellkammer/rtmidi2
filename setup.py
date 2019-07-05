import sys
from setuptools import setup, Extension

version = "0.8.3"  # when changing version, this should reflect what is returned by version()

module_source = 'rtmidi2.pyx'

extension_args = {}
print("version: {version}".format(version=version))

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
    python_requires='>=3.6',
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
        'Programming Language :: Python :: 2.7',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.4',
        'Topic :: Software Development :: Libraries :: Python Modules'
    ],
    description='Python wrapper for RtMidi written in Cython. Allows sending raw messages, multi-port input and sending multiple messages in one call.',
    author='originally by Guido Lorenz, modified by Eduardo Moguillansky',
    author_email='eduardo.moguillansky@gmail.com',
    url="https://github.com/gesellkammer/rtmidi2",        
)
