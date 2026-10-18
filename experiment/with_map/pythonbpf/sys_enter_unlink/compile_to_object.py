from pythonbpf import compile
import logging

compile(filename="test.py", output="test.o", loglevel=logging.DEBUG)
