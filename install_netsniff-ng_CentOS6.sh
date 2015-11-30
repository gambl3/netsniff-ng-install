#!/usr/bin/env bash
# Tested successfully on CentOS 6.7 as of   28 November 15 -gambl3
# Cannot install trafgen or astraceroute. ring.h kicks an undeclared variable 
# I suspect this is due to the lack of TPACKET_V3 support in kernel, a problem with EL systems
# Need to contact devs for this issue.
# Installs: ifpps bpfc flowtop mausezahn *netsniff-ng PCAP tool already has a RPM

DESIRED_TOOLKIT_VERSION="$1" # e.g. ./install_netsniff-ng.sh "0.5.9-rc2+"
DIR=/root
HOST=$(hostname -s)
LOGFILE=netsniff-ng-install.log

exec > >(tee -a "$LOGFILE") 2>&1
echo -e "\n --> Logging stdout & stderr to $LOGFILE"

function cleanup() {
local ORDER=$1
echo "$ORDER Cleaning up any messes!"
cd $DIR
if [ -f libcli-1.8.6-2.el6.rf.x86_64.rpm ]; then
        rm -rf libcli-1.8.6-2.el6.rf.x86_64.rpm
fi

if [ -f libcli-devel-1.8.6-2.el6.rf.x86_64.rpm ]; then
        rm -rf libcli-devel-1.8.6-2.el6.rf.x86_64.rpm
fi
if [ -f epel-release-6-8.noarch.rpm ]; then
        rm -rf epel-release-6-8.noarch.rpm
fi
if [ -d netsniff-ng ]; then
        rm -fr netsniff-ng
fi
}

function check_version() {
local ORDER=$1
echo "$ORDER Checking version!"
if [ -f /usr/local/sbin/mausezahn ]; then
        INSTALLED_VERSION=$(/usr/local/sbin/mausezahn -h | awk '/mausezahn/ && NR == 2 { gsub(",",""); print $2 }')

        if [[ "$INSTALLED_VERSION" == "$DESIRED_TOOLKIT_VERSION" ]]; then
                echo "Current version $DESIRED_TOOLKIT_VERSION is already installed."
		rm -f $0
                exit 0
        fi
fi
}

function install_dependencies()
{
local ORDER=$1
echo -e "$ORDER Checking for dependencies!\n"
if [ ! -f /etc/yum.repos.d/epel.repo ]; then
	rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm && echo "Installed EPEL repo!" || echo "Failed to install EPEL"
fi

yum install -y wget git ccache flex bison GeoIP-devel \
	 libnetfilter_conntrack-devel ncurses-devel \
	 userspace-rcu-devel libpcap-devel zlib-devel \
	 libnet-devel gnuplot cpp libsodium libsodium-devel \
	 libnl3 libnl3-devel libnl3-cli
echo
if [ ! -f /usr/lib64/libcli.so.1.8.6 ]; then
	rpm -ivh http://pkgs.repoforge.org/libcli/libcli-1.8.6-2.el6.rf.x86_64.rpm && echo "Installed libcli!" || echo "Failed to install libcli"
fi
if [ ! -f /usr/include/libcli.h ]; then
	rpm -ivh http://pkgs.repoforge.org/libcli/libcli-devel-1.8.6-2.el6.rf.x86_64.rpm && echo "Installed libcli-devel!" || echo "Failed to install libcli-devel"
fi
}

function install_netsniff-ng() {
local ORDER=$1
local BUILDDIR="/usr/local/netsniff-ng"
echo -e "$ORDER Installing from source!\n"
if git clone https://github.com/netsniff-ng/netsniff-ng.git $BUILDDIR
then
        cd $BUILDDIR
        #Modifiy configure script to use libsodium rather than NaCl
        sed -i 's:\/usr\/include\/nacl:\/usr\/include\/sodium:g' $BUILDDIR
   	sed -i 's:\/usr\/lib:\/usr\/lib64\/:g' $BUILDDIR
   	sed -i 's:\/usr\"nacl\":\"sodium\":g' $BUILDDIR
	#CentOS 6.7 did not like the "case ARPHD_CAIF" statement in dev.c 
	#The include for if_arp.h is broken becase EL6 does does not contain a CAIF definition in if_arp.h
	#For simplicity I am commenting out the CAIF case statement
	sed -i 's;case\ ARPHRD\_CAIF\:;\/\*case\ ARPHRD\_CAIF\:;g'  $BUILDDIR/dev.c 
	sed -i 's:return \"caif\"\;:return \"caif\"\;\*\/:g' $BUILDDIR/dev.c
	./configure 2>&1 > /dev/null
	export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
	./configure && make ifpps bpfc flowtop mausezahn && make ifpps_install bpfc_install flowtop_install mausezahn_install

	if [ $? -eq 0 ]; then
		echo "Netsniff-NG successfully installed!"
	else
		echo "Netsniff-NG tools failed to install"
	fi
else
	echo "Netsniff-NG download failed"
fi
}

function configuration() {
local ORDER=$1
echo -e "$ORDER Configuring the system for best use!\n"

if [ ! -f /etc/ld.so.conf.d/libnl.conf ]; then
	echo "/usr/local/lib" > /etc/ld.so.conf.d/libnl.conf
	ldconfig
fi

if [ -d /etc/sysctl.d ] && [ ! -f /etc/sysctl.d/10-bpf.conf ]; then
cat > /etc/sysctl.d/10-bpf.conf <<EOF
# Enable BPF JIT Compiler (approx. 50ns speed up)
net.core.bpf_jit_enable = 2
EOF
fi
}

# Remove if someone manually left files
cleanup "1.)"
# Check version to update when new is available (specified as argument)
check_version "2.)"
install_dependencies "3.)"
install_netsniff-ng "4.)"
configuration "5.)"
cleanup "6.)"
exit 0
