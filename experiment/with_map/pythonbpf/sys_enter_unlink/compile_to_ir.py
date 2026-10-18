from pythonbpf import compile_to_ir
import logging

compile_to_ir(
   filename="test.py",
   output="test.ll",
   loglevel=logging.DEBUG
)
