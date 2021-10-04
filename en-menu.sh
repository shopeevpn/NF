# Font color
red(){
	echo -e "\033[31m\033[01m$1\033[0m"
    }
green(){
	echo -e "\033[32m\033[01m$1\033[0m"
    }
yellow(){
	echo -e "\033[33m\033[01m$1\033[0m"
}

# Determine whether the mainland VPS, if the IP of CloudFlare cannot be connected, the WARP item is unavailable
ping -4 -c1 -W1 162.159.192.1 >/dev/null 2>&1 && IPV4=1 || IPV4=0
ping -6 -c1 -W1 2606:4700:d0::a29f:c001 >/dev/null 2>&1 && IPV6=1 || IPV6=0
[[ $IPV4$IPV6 = 00 ]] && red " Can’t connect to WARP server, installation is aborted, maybe it’s mainland VPS, problem feedback:[https://github.com/fscarmen/warp/issues] " && rm -f menu.sh && exit 0

# Determine the operating system, only Debian, Ubuntu or Centos is supported. If it is not the above operating system, delete temporary files and exit the script
SYS=$(hostnamectl | tr A-Z a-z | grep system)
[[ $SYS =~ debian ]] && SYSTEM=debian
[[ $SYS =~ ubuntu ]] && SYSTEM=ubuntu
[[ $SYS =~ centos ]] && SYSTEM=centos
[[ -z $SYSTEM ]] && red " This script only supports Debian, Ubuntu or CentOS systems, problem feedback:[https://github.com/fscarmen/warp/issues] " && rm -f menu.sh && exit 0

# The script must be run as root
[[ $(id -u) != 0 ]] && red " The script must be run as root, you can enter sudo -i and re-download and run, feedback:[https://github.com/fscarmen/warp/issues]" && rm -f menu.sh && exit 0

green " Check the environment…… "

# Determine the processor architecture
[[ $(hostnamectl | tr A-Z a-z | grep architecture) =~ arm ]] && ARCHITECTURE=arm64 || ARCHITECTURE=amd64

# Judge virtualization, choose wireguard kernel module or wireguard-go
[[ $(hostnamectl | tr A-Z a-z | grep virtualization) =~ openvz|lxc ]] && LXC=1

# Determine whether the current IPv4 and IPv6, attribution and WARP are enabled
[[ $IPV4 = 1 ]] && LAN4=$(ip route get 162.159.192.1 2>/dev/null | grep -oP 'src \K\S+') &&
		WAN4=$(wget --no-check-certificate -qO- -4 ip.gs) &&
		COUNTRY4=$(wget --no-check-certificate -qO- -4 https://ip.gs/country) &&
		TRACE4=$(wget --no-check-certificate -qO- -4 https://www.cloudflare.com/cdn-cgi/trace | grep warp | cut -d= -f2)				
[[ $IPV6 = 1 ]] && LAN6=$(ip route get 2606:4700:d0::a29f:c001 2>/dev/null | grep -oP 'src \K\S+') &&
		WAN6=$(wget --no-check-certificate -qO- -6 ip.gs) &&
		COUNTRY6=$(wget --no-check-certificate -qO- -6 https://ip.gs/country) &&
		TRACE6=$(wget --no-check-certificate -qO- -6 https://www.cloudflare.com/cdn-cgi/trace | grep warp | cut -d= -f2)

# Judge the current WARP status, determine the variable PLAN, the meaning of the variable PLAN: 01=IPv6, 10=IPv4, 11=IPv4+IPv6, 2=WARP is enabled
[[ $TRACE4 = plus || $TRACE4 = on || $TRACE6 = plus || $TRACE6 = on ]] && PLAN=2 || PLAN=$IPV4$IPV6

# Under the premise of KVM, judge whether the Linux version is less than 5.6, if so, install the wireguard kernel module, and the variable WG=1. 
# Since linux cannot directly use decimals for comparison, use (major version number * 100 + minor version number) for comparison with 506
[[ $LXC != 1 && $(($(uname  -r | cut -d . -f1) * 100 +  $(uname  -r | cut -d . -f2))) -lt 506 ]] && WG=1

# WGCF configuration modification, where 162.159.192.1 and 2606:4700:d0::a29f:c001 used are the IP of engage.cloudflareclient.com
MODIFY1='sed -i "/\:\:\/0/d" wgcf-profile.conf && sed -i "s/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g" wgcf-profile.conf'
MODIFY2='sed -i "7 s/^/PostUp = ip -6 rule add from '$LAN6' lookup main\n/" wgcf-profile.conf && sed -i "8 s/^/PostDown = ip -6 rule delete from '$LAN6' lookup main\n/" wgcf-profile.conf && sed -i "s/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g" wgcf-profile.conf && sed -i "s/1.1.1.1/1.1.1.1,9.9.9.9,8.8.8.8/g" wgcf-profile.conf'
MODIFY3='sed -i "/0\.\0\/0/d" wgcf-profile.conf && sed -i "s/engage.cloudflareclient.com/162.159.192.1/g" wgcf-profile.conf && sed -i "s/1.1.1.1/9.9.9.9,8.8.8.8,1.1.1.1/g" wgcf-profile.conf'
MODIFY4='sed -i "7 s/^/PostUp = ip -4 rule add from '$LAN4' lookup main\n/" wgcf-profile.conf && sed -i "8 s/^/PostDown = ip -4 rule delete from '$LAN4' lookup main\n/" wgcf-profile.conf && sed -i "s/engage.cloudflareclient.com/162.159.192.1/g" wgcf-profile.conf && sed -i "s/1.1.1.1/9.9.9.9,8.8.8.8,1.1.1.1/g" wgcf-profile.conf'
MODIFY5='sed -i "7 s/^/PostUp = ip -4 rule add from '$LAN4' lookup main\n/" wgcf-profile.conf && sed -i "8 s/^/PostDown = ip -4 rule delete from '$LAN4' lookup main\n/" wgcf-profile.conf && sed -i "9 s/^/PostUp = ip -6 rule add from '$LAN6' lookup main\n/" wgcf-profile.conf && sed -i "10 s/^/PostDown = ip -6 rule delete from '$LAN6' lookup main\n/" wgcf-profile.conf && sed -i "s/engage.cloudflareclient.com/162.159.192.1/g" wgcf-profile.conf && sed -i "s/1.1.1.1/9.9.9.9,8.8.8.8,1.1.1.1/g" wgcf-profile.conf'

# VPS current status
status(){
	clear
	yellow "This project specifically adds wgcf network interface for VPS, detailed description: [https://github.com/fscarmen/warp]\nScript features:\n * Support Warp+ account, with third-party flashing Warp+ traffic and upgrading kernel BBR script \n * Intelligently judge the vps operating system: Ubuntu 18.04, Ubuntu 20.04, Debian 10, Debian 11, CentOS 7, CentOS 8, please be sure to choose the LTS system\n * Combining the Linux version and the virtualization method, three WireGuard solutions are automatically selected. Network performance: Core integration WireGuard＞Install kernel module＞wireguard-go\n * Intelligent judgment of the latest version of the WGCF author's github library (Latest release)\n * Intelligent judgment of the hardware structure type: Architecture is AMD or ARM\n * Intelligent analysis Intranet and public network IP generate WGCF configuration file\n * output execution result, prompt whether to use WARP IP, IP attribution\n"
	red "======================================================================================================================\n"
	green " system message：\n	Current operating system：$(hostnamectl | grep -i operating | cut -d : -f2)\n	Kernel：$(uname -r)\n	Processor architecture：$ARCHITECTURE\n	Virtualization：$(hostnamectl | grep -i virtualization | cut -d : -f2) "
	[[ $TRACE4 = plus ]] && green "	IPv4：$WAN4 ( WARP+ IPv4 ) $COUNTRY4 "
	[[ $TRACE4 = on ]] && green "	IPv4：$WAN4 ( WARP IPv4 ) $COUNTRY4 "
	[[ $TRACE4 = off ]] && green "	IPv4：$WAN4 $COUNTRY4 "
	[[ $TRACE6 = plus ]] && green "	IPv6：$WAN6 ( WARP+ IPv6 ) $COUNTRY6 "
	[[ $TRACE6 = on ]] && green "	IPv6：$WAN6 ( WARP IPv6 ) $COUNTRY6 "
	[[ $TRACE6 = off ]] && green "	IPv6：$WAN6 $COUNTRY6 "
	[[ $TRACE4 = plus || $TRACE6 = plus ]] && green "	WARP+ is turned on"
	[[ $TRACE4 = on || $TRACE6 = on ]] && green "	WARP is on" 	
	[[ $TRACE4 = off && $TRACE6 = off ]] && green "	WARP is not turned on"
 	red "\n======================================================================================================================\n"
		}

# WGCF installation
install(){
	# Script start time
	start=$(date +%s)
	
	#Enter the Warp+ account (if any), limit the number of digits to be empty or 26 to prevent input errors
	read -p "If you have a Warp+ License, please enter it, no press enter to continue:" LICENSE
	i=5
	until [[ -z $LICENSE || ${#LICENSE} = 26 || $i = 1 ]]
		do
			let i--
			red " License should be 26 digits "
			read -p " Please re-enter the Warp+ License, there is no return to continue ($i time remaining): " LICENSE
		done
	[[ $i = 1 ]] && red " Input errors up to 5 times, the script exits " && exit 0
	
	green " Progress 1/3: Install system dependencies"

	# First delete the files that were installed before, which may cause the failure, add environment variables
	rm -f /usr/local/bin/wgcf /etc/wireguard/wgcf.conf /usr/bin/wireguard-go  wgcf-account.toml  wgcf-profile.conf
	[[ $PATH =~ /usr/local/bin ]] || export PATH=$PATH:/usr/local/bin
	
        # Select the dependencies that need to be installed according to the system
	debian(){
		# Update source
		apt -y update

		# Add the backports source before you can install wireguard-tools
		apt -y install lsb-release
		echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" > /etc/apt/sources.list.d/backports.list

		# Update source again
		apt -y update

		# Install some necessary network toolkits and wireguard-tools (Wire-Guard configuration tools: wg, wg-quick)
		apt -y --no-install-recommends install net-tools iproute2 openresolv dnsutils wireguard-tools

		# If the Linux version is lower than 5.6 and it is kvm, install the wireguard kernel module
		[[ $WG = 1 ]] && apt -y --no-install-recommends install linux-headers-$(uname -r) && apt -y --no-install-recommends install wireguard-dkms
		}
		
	ubuntu(){
		# Update source
		apt -y update

		# Install some necessary network toolkits and wireguard-tools (Wire-Guard configuration tools: wg, wg-quick)
		apt -y --no-install-recommends install net-tools iproute2 openresolv dnsutils wireguard-tools
		}
		
	centos(){
		# Install some necessary network toolkits and wireguard-tools (Wire-Guard configuration tools: wg, wg-quick)
		yum -y install epel-release
		yum -y install curl net-tools wireguard-tools

		# If the Linux version is lower than 5.6 and it is kvm, install the wireguard kernel module
		[[ $WG = 1 ]] && curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo &&
		yum -y install epel-release wireguard-dkms

		# Upgrading all packages also upgrades software and system kernel
		yum -y update
		}

	$SYSTEM

	# Install and certify WGCF
	green " Progress 2/3: Install WGCF "

	# Determine the latest version of wgcf. If it cannot be obtained due to github interface issues, the default is v2.2.8
	latest=$(wget --no-check-certificate -qO- -t1 -T1 "https://api.github.com/repos/ViRb3/wgcf/releases/latest" | grep "tag_name" | head -n 1 | cut -d : -f2 | sed 's/\"//g;s/v//g;s/,//g;s/ //g')
	[[ -z $latest ]] && latest='2.2.8'

	# Install wgcf and try to download the latest official version. If the official wgcf download is unsuccessful, the CDN of jsDelivr will be used to better support dual stack
	wget --no-check-certificate -t1 -T1 -N -O /usr/local/bin/wgcf https://github.com/ViRb3/wgcf/releases/download/v$latest/wgcf_${latest}_linux_$ARCHITECTURE
	[[ $? != 0 ]] && wget --no-check-certificate -N -O /usr/local/bin/wgcf https://cdn.jsdelivr.net/gh/fscarmen/warp/wgcf_${latest}_linux_$ARCHITECTURE

	# Add execute permission
	chmod +x /usr/local/bin/wgcf

	# For LXC, install wireguard-go
	[[ $LXC = 1 ]] && wget --no-check-certificate -N -P /usr/bin https://cdn.jsdelivr.net/gh/fscarmen/warp/wireguard-go && chmod +x /usr/bin/wireguard-go

	# Register a WARP account (wgcf-account.toml file will be generated to save account information)
	yellow " WGCF 注册中…… "
	until [[ -e wgcf-account.toml ]]
	  do
	   echo | wgcf register >/dev/null 2>&1
	done
	
	# If you have a Warp+ account, modify the license and upgrade
	[[ -n $LICENSE ]] && yellow " Upgrade Warp+ account " && sed -i "s/license_key.*/license_key = \"$LICENSE\"/g" wgcf-account.toml &&
	( wgcf update || red " If the upgrade fails, the Warp+ account is wrong or more than 5 devices have been activated, the free Warp account will be automatically replaced to continue" )
	
	# Generate Wire-Guard configuration file (wgcf-profile.conf)
	wgcf generate >/dev/null 2>&1

	# Modify the configuration file
	echo $MODIFY | sh

	# Copy wgcf-profile.conf to /etc/wireguard/ and name it wgcf.conf
	cp -f wgcf-profile.conf /etc/wireguard/wgcf.conf

	# Automatically brush until successful (warp bug, sometimes unable to obtain the ip address), record the new IPv4 and IPv6 address and the attribution
	green " Progress 3/3: Run WGCF"
	yellow " Obtaining WARP IP in the background…… "

	# Clear the relevant variable value before
	unset WAN4 WAN6 COUNTRY4 COUNTRY6 TRACE4 TRACE6

	wg-quick up wgcf >/dev/null 2>&1
	WAN4=$(wget --no-check-certificate -T1 -t1 -qO- -4 ip.gs)
	WAN6=$(wget --no-check-certificate -T1 -t1 -qO- -6 ip.gs)
	until [[ -n $WAN4 && -n $WAN6 ]]
	  do
	   wg-quick down wgcf >/dev/null 2>&1
	   wg-quick up wgcf >/dev/null 2>&1
	   WAN4=$(wget --no-check-certificate -T1 -t1 -qO- -4 ip.gs)
	   WAN6=$(wget --no-check-certificate -T1 -t1 -qO- -6 ip.gs)
	done
	COUNTRY4=$(wget --no-check-certificate -qO- -4 https://ip.gs/country)
	TRACE4=$(wget --no-check-certificate -qO- -4 https://www.cloudflare.com/cdn-cgi/trace | grep warp | cut -d= -f2)
	COUNTRY6=$(wget --no-check-certificate -qO- -6 https://ip.gs/country)
	TRACE6=$(wget --no-check-certificate -qO- -6 https://www.cloudflare.com/cdn-cgi/trace | grep warp | cut -d= -f2)

	# Set to boot up, due to warp bugs, sometimes the ip address cannot be obtained, and the network is automatically refreshed after the restart is added to the scheduled task
	systemctl enable wg-quick@wgcf >/dev/null 2>&1
	grep -qE '^@reboot[ ]*root[ ]*bash[ ]*/etc/wireguard/WARP_AutoUp.sh' /etc/crontab || echo '@reboot root bash /etc/wireguard/WARP_AutoUp.sh' >> /etc/crontab
	echo '[[ $(type -P wg-quick) ]] && [[ -e /etc/wireguard/wgcf.conf ]] && wg-quick up wgcf >/dev/null 2>&1 &&' > /etc/wireguard/WARP_AutoUp.sh
	echo 'until [[ -n $(wget --no-check-certificate -T1 -t1 -qO- -4 ip.gs) && -n $(wget --no-check-certificate -T1 -t1 -qO- -6 ip.gs) ]]' >> /etc/wireguard/WARP_AutoUp.sh
	echo '	do' >> /etc/wireguard/WARP_AutoUp.sh
	echo '		wg-quick down wgcf >/dev/null 2>&1' >> /etc/wireguard/WARP_AutoUp.sh
	echo '		wg-quick up wgcf >/dev/null 2>&1' >> /etc/wireguard/WARP_AutoUp.sh
 	echo '	done' >> /etc/wireguard/WARP_AutoUp.sh

	# Prefer IPv4 network
	[[ -e /etc/gai.conf ]] && [[ $(grep '^[ ]*precedence[ ]*::ffff:0:0/96[ ]*100' /etc/gai.conf) ]] || echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf

	# Delete temporary files
	rm -f wgcf-account.toml  wgcf-profile.conf menu.sh

	# The result shows that the script running time
	[[ $TRACE4 = plus ]] && green " IPv4：$WAN4 ( WARP+ IPv4 ) $COUNTRY4 "
	[[ $TRACE4 = on ]] && green " IPv4：$WAN4 ( WARP IPv4 ) $COUNTRY4 "
	[[ $TRACE4 = off || -z $TRACE4 ]] && green " IPv4：$WAN4 $COUNTRY4 "
	[[ $TRACE6 = plus ]] && green " IPv6：$WAN6 ( WARP+ IPv6 ) $COUNTRY6 "
	[[ $TRACE6 = on ]] && green " IPv6：$WAN6 ( WARP IPv6 ) $COUNTRY6 "
	[[ $TRACE6 = off || -z $TRACE6 ]] && green " IPv6：$WAN6 $COUNTRY6 "
	end=$(date +%s)
	[[ $TRACE4 = plus || $TRACE6 = plus ]] && green " Congratulations! WARP+ has been turned on, the total time spent: $(( $end - $start )) seconds "
	[[ $TRACE4 = on || $TRACE6 = on ]] && green " Congratulations! WARP has been turned on, total time spent: $(( $end - $start )) seconds " 	
	[[ $TRACE4 = off && $TRACE6 = off ]] && red " WARP installation failed, problem feedback:[https://github.com/fscarmen/warp/issues] "
		}

# Shut down the WARP network interface and delete WGCF
uninstall(){
	unset WAN4 WAN6 COUNTRY4 COUNTRY6
	systemctl disable wg-quick@$(wg | grep interface | cut -d : -f2) >/dev/null 2>&1
	wg-quick down $(wg | grep interface | cut -d : -f2) >/dev/null 2>&1
	[[ $SYSTEM = centos ]] && yum -y autoremove wireguard-tools wireguard-dkms 2>/dev/null || apt -y autoremove wireguard-tools wireguard-dkms 2>/dev/null
	rm -rf /usr/local/bin/wgcf /etc/wireguard /usr/bin/wireguard-go /etc/wireguard wgcf-account.toml wgcf-profile.conf menu.sh
	[[ -e /etc/gai.conf ]] && sed -i '/^precedence[ ]*::ffff:0:0\/96[ ]*100/d' /etc/gai.conf
	sed -i '/^@reboot.*WARP_AutoUp/d' /etc/crontab
	WAN4=$(wget --no-check-certificate -T1 -t1 -qO- -4 ip.gs)
	WAN6=$(wget --no-check-certificate -T1 -t1 -qO- -6 ip.gs)
	COUNTRY4=$(wget --no-check-certificate -T1 -t1 -qO- -4 https://ip.gs/country)
	COUNTRY6=$(wget --no-check-certificate -T1 -t1 -qO- -6Has been completely deleted! https://ip.gs/country)
	[[ -z $(wg) ]] >/dev/null 2>&1 && green " WGCF Has been completely deleted!\n IPv4：$WAN4 $COUNTRY4\n IPv6：$WAN6 $COUNTRY6 " || red " Not cleaned up, please restart (reboot) and try to delete again "
		}

# 安装BBR
bbrInstall() {
	red "\n=============================================================="
	green "BBR、Mature works of [ylx2016] used by DD script, address[https://github.com/ylx2016/Linux-NetSpeed]，Please be familiar with"
	yellow "1.Installation script [Recommend original BBR+FQ]"
	yellow "2.Back to home"
	red "=============================================================="
	read -p "please choose：" BBR
	case "$BBR" in
		1 ) wget --no-check-certificate -N "https://raw.githubusercontent.com/shopeevpn/NF/main/en-tcp.sh" && chmod +x en-tcp.sh && ./en-tcp.sh;;
		2 ) menu$PLAN;;
		* ) red "Please enter the correct number [1-2]"; sleep 1; bbrInstall;;
		esac
		}

input() {
	read -p "Please enter Warp+ ID:" ID
	i=5
	until [[ ${#ID} = 36 || $i = 1 ]]
		do
		let i--
		red " Warp+ ID should be 36 digits"
		read -p " Please re-enter the Warp+ ID ($i remaining):" ID
	done
	[[ $i = 1 ]] && red " Input errors up to 5 times, the script exits " && exit 0
	}

# Brush Warp+ traffic
plus() {
	red "\n=============================================================="
	green " For Warp+ traffic, you can choose the mature works of the following two authors. Please be familiar with:\n * [ALIILAPRO], address [https://github.com/ALIILAPRO/warp-plus-cloudflare]\n * [mixool], address [https://github.com/mixool/across/tree/master/wireguard]\n Download address: https://1.1.1.1/, visit and take care of the ID of Apple Outer Area\n Get Warp+ ID and fill in below. Method: Menu three in the upper right corner of the App --> Advanced --> Diagnosis --> ID\n Important: The traffic has not increased after flashing the script. Processing: Menu three in the upper right corner --> Advanced --> Connection options --> Reset encryption Key\n It is best to cooperate with screen to run tasks in the background "
	yellow "1.Run the [ALIILAPRO] script "
	yellow "2.Run the [mixool] script "
	yellow "3.Back to home"
	red "=============================================================="
	read -p "please choose：" CHOOSEPLUS
	case "$CHOOSEPLUS" in
		1 ) input
		    [[ $(type -P git) ]] || apt -y install git 2>/dev/null || yum -y install git 2>/dev/null
		    [[ $(type -P python3) ]] || apt -y install python3 2>/dev/null || yum -y install python3 2>/dev/null
		    [[ -d ~/warp-plus-cloudflare ]] || git clone https://github.com/aliilapro/warp-plus-cloudflare.git
		    echo $ID | python3 ~/warp-plus-cloudflare/wp-plus.py;;
		2 ) input
		    wget --no-check-certificate -N https://cdn.jsdelivr.net/gh/mixool/across/wireguard/warp_plus.sh
		    sed -i "s/eb86bd52-fe28-4f03-a944-60428823540e/$ID/g" warp_plus.sh
		    bash warp_plus.sh;;
		3 ) menu$PLAN;;
		* ) red "Please enter the correct number [1-3]"; sleep 1; plus;;
		esac
		}

# IPv6
menu01(){
	status
	green " 1. Add IPv4 network interface for IPv6 only "
	green " 2. Add dual-stack network interface for IPv6 only "
	green " 3. Shut down the WARP network interface and delete WGCF "
	green " 4. Upgrade kernel, install BBR, DD script "
	green " 5. Brush Warp+ traffic "
	green " 0. Exit script \n "
	read -p "Please enter the number:" CHOOSE01
		case "$CHOOSE01" in
		1 ) 	MODIFY=$MODIFY1;	install;;
		2 )	MODIFY=$MODIFY2;	install;;
		3 ) 	uninstall;;
		4 )	bbrInstall;;
		5 )	plus;;
		0 ) 	exit 1;;
		* ) 	red "Please enter the correct number [0-5]"; sleep 1; menu01;;
		esac
		}

# IPv4
menu10(){
	status
	green " 1. Add IPv6 network interface for IPv4 only "
	green " 2. Add dual-stack network interface for IPv4 only "
	green " 3. Shut down the WARP network interface and delete WGCF "
	green " 4. Upgrade kernel, install BBR, DD script "
	green " 5. Brush Warp+ traffic "
	green " 0. Exit script \n "
	read -p "Please enter the number:" CHOOSE10
		case "$CHOOSE10" in
		1 ) 	MODIFY=$MODIFY3;	install;;
		2 ) 	MODIFY=$MODIFY4;	install;;
		3 ) 	uninstall;;
		4 )	bbrInstall;;
		5 )	plus;;
		0 ) 	exit 1;;
		* ) 	red "Please enter the correct number [0-5]"; sleep 1; menu10;;
		esac
		}

# IPv4+IPv6
menu11(){ 
	status
	green " 1. Add WARP dual stack network interface to native dual stack "
	green " 2. Shut down the WARP network interface and delete WGCF "
	green " 3. Upgrade kernel, install BBR, DD script "
	green " 4. Brush Warp+ traffic "
	green " 0. Exit script \n "
	read -p "Please enter the number:" CHOOSE11
		case "$CHOOSE11" in
		1 ) 	MODIFY=$MODIFY5;	install;;
		2 ) 	uninstall;;
		3 )	bbrInstall;;
		4 )	plus;;
		0 ) 	exit 1;;
		* ) 	red "Please enter the correct number [0-4]"; sleep 1; menu11;;
		esac
		}

# 已开启 warp 网络接口
menu2(){ 
	status
	green " 1. Shut down the WARP network interface and delete WGCF "
	green " 2. Upgrade kernel, install BBR, DD script "
	green " 3. Brush Warp+ traffic "
	green " 0. Exit script \n "
	read -p "Please enter the number:" CHOOSE2
        	case "$CHOOSE2" in
		1 ) 	uninstall;;
		2 )	bbrInstall;;
		3 )	plus;;
		0 ) 	exit 1;;
		* ) 	red "Please enter the correct number [0-3]"; sleep 1; menu2;;
		esac
		}

menu$PLAN
