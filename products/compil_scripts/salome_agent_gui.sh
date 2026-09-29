#!/bin/bash

echo "##########################################################################"
echo "SALOME_AGENT_GUI" $VERSION
echo "##########################################################################"

mkdir -p "${PRODUCT_INSTALL}"
${PYTHONBIN} -m venv ${PRODUCT_INSTALL}
unset PYTHONPATH
source ${PRODUCT_INSTALL}/bin/activate
cd ${SOURCE_DIR}

# A leftover setuptools build/ dir would ship files deleted from the sources.
rm -rf build salome-agent/build
${PRODUCT_INSTALL}/bin/pip3 install ./salome-agent .
if [ $? -ne 0 ]; then
    echo "FATAL: could not install salome-agent-gui"
    exit 1
fi

cp ${SOURCE_DIR}/salome-agent-gui.sh ${PRODUCT_INSTALL}/bin/salome-agent-gui.sh
if [ $? -ne 0 ]; then
    echo "FATAL: could not find salome-agent-gui.sh"
    exit 2
fi
chmod 755 ${PRODUCT_INSTALL}/bin/salome-agent-gui.sh

# Seed config for ~/.config/salome/salome-agent.json on first launch.
cp ${SOURCE_DIR}/salome-agent/config.example.json \
   ${PRODUCT_INSTALL}/lib/python${PYTHON_VERSION}/site-packages/salome_agent_gui/config.example.json
if [ $? -ne 0 ]; then
    echo "FATAL: could not copy config.example.json"
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
