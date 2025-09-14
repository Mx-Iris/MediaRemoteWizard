project_path=$(cd `dirname $0`; pwd)

project_name="MediaRemoteWizard"

scheme_name="MediaRemoteWizard"

development_mode="Debug"

build_path=${project_path}/build

xcodebuild build \
-scheme ${scheme_name} \
-configuration ${development_mode} \
-destination 'generic/platform=macOS' \
CONFIGURATION_BUILD_DIR=${build_path} \
ARCHS="x86_64 arm64e"

exit 0


