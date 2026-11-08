#!/bin/bash

echo "##########################################################################"
echo "SALOME_AGENT_GUI" $VERSION
echo "##########################################################################"
# One SALOME plugin, submenu Tools > Plugins > AI tools (SALOME agent,
# Documentation (RAG), MCP server), whose window offers three
# assistants: Classical RAG and Agentic RAG over the SALOME documentation
# (raglib, formerly the separate sarag / salome-assistant product) and the
# Agentic assistant that builds models. One config file holds all three:
# ~/.config/salome/salome-agent.json, seeded from salome_agent_gui/config.example.json.
# SALOME_AGENT_GUI_RAG=0 leaves out the documentation modes (torch, chromadb...,
# about 2 GB).
RAG=${SALOME_AGENT_GUI_RAG:-1}

mkdir -p "${PRODUCT_INSTALL}"
${PYTHONBIN} -m venv ${PRODUCT_INSTALL}
unset PYTHONPATH
source ${PRODUCT_INSTALL}/bin/activate
# Build from a copy in BUILD_DIR: pip builds in-tree, and its build/ and
# *.egg-info must not land in (or be reused from) SOURCE_DIR.
# The pip cache lives next to BUILD_DIR, not in it: BUILD_DIR is wiped below,
# and an empty cache makes every build re-download (and re-resolve) everything.
PIP_CACHE=${BUILD_DIR}_pipcache
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR} ${PIP_CACHE}
tar -C ${SOURCE_DIR} --exclude=.git --exclude=./.venv --exclude=./build --exclude=./salome-agent/build \
    --exclude='*.egg-info' -cf - . | tar -C ${BUILD_DIR} -xf -
if [ $? -ne 0 ]; then
    echo "FATAL: could not copy the sources to ${BUILD_DIR}"
    exit 1
fi
cd ${BUILD_DIR}
# constraints.txt pins every dependency to the versions the tests ran with, so
# a clean install gets the same set each time instead of whatever PyPI resolves.
CONSTRAINTS=""
if [ -f constraints.txt ]; then
    CONSTRAINTS="-c constraints.txt"
else
    echo "WARNING: no constraints.txt in this salome-agent-gui checkout, dependencies are not pinned"
fi
if [ "${RAG}" = 0 ]; then
    ${PRODUCT_INSTALL}/bin/pip3 install --cache-dir=${PIP_CACHE} ${CONSTRAINTS} ./salome-agent .
else
    # CPU-only torch first: from PyPI, pip would pull several GB of CUDA wheels.
    ${PRODUCT_INSTALL}/bin/pip3 install --cache-dir=${PIP_CACHE} torch \
        --index-url https://download.pytorch.org/whl/cpu
    if [ $? -ne 0 ]; then
        echo "FATAL: could not install CPU torch for the documentation modes"
        exit 1
    fi
    ${PRODUCT_INSTALL}/bin/pip3 install --cache-dir=${PIP_CACHE} ${CONSTRAINTS} ./salome-agent '.[rag]'
fi
if [ $? -ne 0 ]; then
    echo "FATAL: could not install salome-agent-gui"
    exit 1
fi
# pip succeeding is not enough: a resolve can pick versions that do not run.
# Building the agent graph imports what a GUI turn needs.
# -I: python -c would otherwise import the copy in BUILD_DIR (the cwd).
# ...and salome-agent-mcp (SALOME as tools for Claude Desktop / Claude Code).
${PRODUCT_INSTALL}/bin/python3 -I -c "import salome_agent_gui.app, salome_agent_gui.mcp_server, mcp.server.mcpserver; from salome_agent.graph import build_graph; build_graph(batch=True)"
if [ $? -ne 0 ]; then
    echo "FATAL: the installed salome-agent-gui does not import"
    exit 6
fi
if [ "${RAG}" != 0 ]; then
    ${PRODUCT_INSTALL}/bin/python3 -I -c "from salome_agent_gui import rag_backend; rag_backend.ensure_path(); import core"
    if [ $? -ne 0 ]; then
        echo "FATAL: the documentation modes (raglib) do not import"
        exit 7
    fi
fi

cp ${SOURCE_DIR}/salome-agent-gui.sh ${PRODUCT_INSTALL}/bin/salome-agent-gui.sh
if [ $? -ne 0 ]; then
    echo "FATAL: could not find salome-agent-gui.sh"
    exit 2
fi
chmod 755 ${PRODUCT_INSTALL}/bin/salome-agent-gui.sh

# Seed config for ~/.config/salome/salome-agent.json on first launch: the GUI's
# own example (pip installs it as package data), the engine's settings plus
# gui.mode and the rag section. Do not replace it with salome-agent's
# config.example.json, which has no rag section.
${PRODUCT_INSTALL}/bin/python3 -I -c "from salome_agent_gui import rag_backend; rag_backend.default_rag()"
if [ $? -ne 0 ]; then
    echo "FATAL: the installed config.example.json has no rag section"
    exit 3
fi

# GUI plugin: SALOME's plugins manager scans <X>_ROOT_DIR/share/salome/plugins
# for *_plugins.py (SALOME_AGENT_GUI_ROOT_DIR is set by env_scripts/salome_agent_gui.py)
# and puts that directory on sys.path, so sagui_launcher and the in-GUI agent
# server packages (stdlib + SALOME only) are importable in SALOME's Python.
PLUGIN_DIR=${PRODUCT_INSTALL}/share/salome/plugins/salome_agent_gui
mkdir -p ${PLUGIN_DIR}
for f in salome_plugins.py sagui_launcher.py; do
    cp ${SOURCE_DIR}/${f} ${PLUGIN_DIR}/${f}
    if [ $? -ne 0 ]; then
        echo "FATAL: could not install GUI plugin file ${f}"
        exit 4
    fi
done
for d in agent_server executor; do
    rm -rf ${PLUGIN_DIR}/${d}
    cp -r ${SOURCE_DIR}/salome-agent/${d} ${PLUGIN_DIR}/${d}
    if [ $? -ne 0 ]; then
        echo "FATAL: could not install agent server package ${d}"
        exit 5
    fi
done
find ${PLUGIN_DIR} -name __pycache__ -prune -exec rm -rf {} +

echo
echo "########## END"
