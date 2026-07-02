#!/usr/bin/env python3
"""Entry point for the capture server — run with ``python main.py`` or directly."""

import sys
import os

# Ensure the src directory is on the path when running main.py directly
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))

from server import main


if __name__ == "__main__":
    raise SystemExit(main())
