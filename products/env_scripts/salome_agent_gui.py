#!/usr/bin/env python
#-*- coding:utf-8 -*-

import os.path

def set_env(env, prereq_dir, version):
  env.set('SALOME_AGENT_GUI_ROOT_DIR', prereq_dir)
  env.set('SALOME_AGENT_GUI', os.path.join(prereq_dir, 'bin', 'salome-agent-gui.sh'))

def set_nativ_env(env):
  pass
