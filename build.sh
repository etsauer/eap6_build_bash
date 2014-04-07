#!/bin/bash
#set -x
BUILD_NAME=jboss_TU_standalone_build
SCRIPTS_BASE=/opt/jboss/webhosting/scripts
BINARY_BASE=/opt/jboss/60
BINARY_VERSION=jboss-eap-6.0
JBOSS_CVS_PROJECT=jboss
JBOSS_TMP_DIR=/tmp/jboss_install
jboss_user=`stat -c %U /opt/jboss`

build_latest() {
	local dest=$1
	echo "Pulling down build from $JBOSS_INSTALL_ROOT. This may take a few minutes."
	#checkout &> build.out  #OLD WAY
	pull_jboss #NEW WAY
	
	#remove all CVS directories
	#echo "Cleaning up CVS insertions..."
	#find /tmp/$BUILD_NAME -depth -name 'CVS' -exec rm -rf '{}' \;

	echo "Building package..."
	package $dest
}

#Deprecated: CVS proved not to be a viable option for storing jars, so we switched to using rsync (below)
checkout() {
	#Clean out old jboss builds
	rm -rf /tmp/$JBOSS_CVS_PROJECT
	rm -rf /tmp/$BUILD_NAME

	local current_dir=`pwd`
	cd /tmp
	cvs co $JBOSS_CVS_PROJECT
	mv $JBOSS_CVS_PROJECT $BUILD_NAME
	cd $current_dir
}

pull_jboss() {
	#Clean out old jboss builds
	rm -rf $JBOSS_TMP_DIR
	rm -rf /tmp/$BUILD_NAME
	mkdir $JBOSS_TMP_DIR

	rsync -av -e ssh $JBOSS_INSTALL_ROOT/binaries $JBOSS_TMP_DIR 2>1 1>build.out
	rsync -av -e ssh $JBOSS_INSTALL_ROOT/scripts $JBOSS_TMP_DIR 2>1 1>build.out
	mv $JBOSS_TMP_DIR /tmp/$BUILD_NAME
}

push_jboss() {
	# Clean out jboss dir
	rm -rf ~/jboss
	mkdir -p ~/jboss/{binaries,scripts}

	# Take snapshot of current jboss project
	echo "Taking snapshot of most current version..."
	build_latest ~/jboss

	# Copy in current state of jboss build
	echo "Pushing new version.."
	cp -r $BINARY_BASE/{jboss-eap-6.0,jboss-eap-6.0.1} ~/jboss/binaries/
	cp -r $SCRIPTS_BASE/* ~/jboss/scripts/
	echo "rsync -av --progress -e ssh ~/jboss/ $JBOSS_INSTALL_ROOT"
	rsync -av --progress -e ssh ~/jboss/ $JBOSS_INSTALL_ROOT 2>1 1>build.out
}

extract () {
	local tarball=$1
	echo "Extracting $tarball"

	# run the rest as jboss user
	sesu - $jboss_user <<EOFADD

	tar xzf $tarball -C /tmp
	
	mkdir -p $BINARY_BASE
	cp -R /tmp/$BUILD_NAME/binaries/* $BINARY_BASE
	
	mkdir -p $SCRIPTS_BASE
	cp -R /tmp/$BUILD_NAME/scripts/* $SCRIPTS_BASE

	rm -rf /tmp/$BUILD_NAME
EOFADD
	make_links
}

make_links() {
	find /opt/jboss/ -maxdepth 2 -name "jboss-eap-*" | while read line
	do
		sesu - $jboss_user <<EOFADD
		mkdir -p $line/modules/org/jboss/as/web/main/lib/linux-x86_64
		ln -s /usr/lib64/libcrypto.so.10 $line/modules/org/jboss/as/web/main/lib/linux-x86_64/libcrypto.so
		ln -s /usr/lib64/libapr-1.so.0 $line/modules/org/jboss/as/web/main/lib/linux-x86_64/libapr-1.so
		ln -s /usr/lib64/libssl.so.10 $line/modules/org/jboss/as/web/main/lib/linux-x86_64/libssl.so
EOFADD
	done
}

configure_app-group_install() {
	appgroup=$1
	properties_files=$2
	echo "Configuring $appgroup using $properties_files"

	sesu - $jboss_user <<EOFADD
	# Moving SSL directory out of /opt/$appgroup. May as well do it here. -NTM
	mkdir -p /opt/jboss/apps/$appgroup/ssl
	cp $properties_files/* /opt/jboss/apps/$appgroup/
EOFADD
}

install_app-group() {
	appgroup=$1
	build_home=$JBOSS_BUILD_HOME

	sesu - $jboss_user <<EOFADD
	$build_home/bin/install_app-group.sh $appgroup $build_home
EOFADD
}

clean() {
	appgroup=$1
	rm -R $SCRIPTS_BASE
	rm -R /opt/jboss/apps/$appgroup
	rm -R /tmp/$BUILD_NAME
	rm -R $BINARY_BASE/$BINARY_VERSION
}

package() {
	local target=$1

	# Assumes a checkout() to /tmp
	local current_dir
	local filename=JBoss_TU_$(date +%Y%m%d-%H%M%S).tgz
	cd /tmp
	tar czf $target/$filename $BUILD_NAME
	chmod a+r $target/$filename
	echo "Build created: $target/$filename"

	#clean up /tmp
	rm -rf $BUILD_NAME

	cd $current_dir
}

show_help() {
	echo "RUN AS OWN USER -- SCRIPT WILL sesu AS NEEDED."
	echo "Usage: build.sh --package {/path/to/tarball/directory}|--extract {tarball}|--setup {app-group} {/path/to/properties-files/dir}|--install {app-group}"
	echo
	echo "--build_tar - Creates JBoss tarball of latest stable binaries and scripts."
	echo "--extract - Extracts JBoss tarball and installs binaries and scripts."
	echo "--setup - Creates file system for app group and places installation properties files in preparation for installation."
	echo "--install - Kicks off installation of app group and all servers."
	echo
	echo "JBOSS BUILD INSTRUCTIONS"
	echo "	1. Run $(basename $0) --build_tar {/where/to/place/archive/} (i.e. $(basename $0) --build_tar ~) to create a tarball of binaries and scripts and place it in the specified directory."
	echo "	2. Place build script, tarball, and all app group and server properties files (filled out with desired configuration) on server or in remote location accessible by jboss id."
	echo "	3. Run $(basename $0) --extract {tarball} (i.e. $(basename $0) --extract JBoss_TU_$(date +%Y%m%d-%H%M%S).tgz) to extract and place binaries/scripts."
	echo "	4. Run $(basename $0) --setup {app-group} {/path/to/properties-files/dir} (i.e. $(basename $0) --setup tad ~/jboss_build/sample_installs/tad) to create app-group file system and place properties files in the expected location."
	echo "	5. Run $(basename $0) --install {app-group} (i.e. $(basename $0) --install tad) to install and configure app-group and all subsequent servers."
}

if [[ -z "$JBOSS_BUILD_HOME" ]]
then
	echo "Please set JBOSS_BUILD_HOME to location of jboss_build directory. No trailing slash."
	echo
	echo "Example: export JBOSS_BUILD_HOME=~/jboss_build"
	exit 1
fi

if [[ -z "$JBOSS_INSTALL_ROOT" ]]
then
        echo "Please set JBOSS_INSTALL_ROOT to location of the jboss install directory. No trailing slash."
        echo
        echo "Example: export JBOSS_INSTALL_ROOT=[username]@host:/opt/webhosting/jboss"
        exit 1
fi


if [[ -z "$@" ]]
then
	show_help
	exit
fi

if ! options=$(getopt -o e:b:s::i:c:hm -l extract:,build_tar:,setup::,install:,help,clean:,push -- "$@")
then
	echo "Use --help for usage information."
        exit 1
fi

while [ $# -gt 0 ]
do
        case $1 in
	-h|--help) show_help ;;
        -e|--extract) extract $2 ; shift;;
	-b|--build_tar) build_latest $2 ; shift;;
        -s|--setup) configure_app-group_install $2 $3 ; shift;;
	-i|--install) install_app-group $2; shift;;
	-c|--clean) clean $2 ; shift;;
	-m) make_links ; shift;;
	--push) push_jboss ; shift;;
        (--) shift; break;;
        (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
        (*) break;;
        esac
        shift
done
