#!/bin/bash

if [ ! -d .venv ]; then
  echo "Creating virtual environment"
  python -m venv .venv
  echo "Setting up virtual environment"
  pip install -r requirements.txt
else
  echo "Virtual environment was previously setup.  If you need to redo this, please remove the .venv directory"
fi
