#!/bin/bash

mkdir /iso &>/dev/null
mv ./rhel-server-7.1-x86_64-dvd.iso /iso/ &>/dev/null
mv ./rhel-osp-6.0-2015-02-23.2-x86_64.iso /iso/ &>/dev/null


if [ ! -f /iso/rhel-server-7.1-x86_64-dvd.iso ] || [ ! -f /iso/rhel-osp-6.0-2015-02-23.2-x86_64.iso ]
then
	echo -e "检查/iso/目录是否存在下列文件\nrhel-server-7.1-x86_64-dvd.iso \nrhel-osp-6.0-2015-02-23.2-x86_64.iso \n" && exit
fi

rm -rf /etc/yum.repos.d/*
if [ $? == 0 ] ;then echo -e "清除全部的repo文件 成功\n" ;fi 
cat <<EOF >/etc/yum.repos.d/cdrom.repo
[cdrom]
name = cdrom 
baseurl=file:///mnt/
gpgcheck = 0
EOF
if [ $? == 0 ] ;then echo -e "创建cdrom.repo文件 成功\n" ;fi 

#挂载光盘，安装前期必备的软件包
umount /mnt
mount /iso/rhel-server-7.1-x86_64-dvd.iso /mnt/
yum repolist && yum makecache 
yum install httpd chrony ntpdate expect -y
if [ $? == 0 ] ;then echo -e "安装httpd chrony ntpdate expect成功\n" ;fi 

echo -e "目前hosts文件内容如下：\n"
cat /etc/hosts

#判断是否需要改写hosts文件
read -p"上述/etc/hosts配置是否正确？[yes or no] ：" yn
if [ $yn == "n" ] || [ $yn == "no" ]
then 
	read -p "input ntp_server ip :" ntpip
	read -p "input controller_node ip :" conip
	read -p "input compute_server ip :" comip
	
	#把变量写入hosts文件
	cat <<EOF >>/etc/hosts
	${ntpip}	ntp
	${conip}	controller
	${comip}	compute
EOF

	echo -e "目前hosts文件内容如下：\n"
	cat /etc/hosts

else 
	#从hosts配置，读入相应变量中
	ntpip=`cat /etc/hosts |grep -v localhost |grep ntp |awk '{print $1}'`
	conip=`cat /etc/hosts |grep -v localhost |grep controller |awk '{print $1}'`
	comip=`cat /etc/hosts |grep -v localhost |grep compute |awk '{print $1}'`

fi


#获取用户输入的密码
read -p "输入远端节点root密码（要求全部节点密码一致）：" nodepw1
if [ ${nodepw1} == "" ]
then  
	echo -e "密码不能为空,请重新输入.\n" 
	read -p "输入远端节点root密码（要求全部节点密码一致）：" nodepw1
fi

read -p "请重复输入远端节点root密码（要求全部节点密码一致）：" nodepw2
if [ ${nodepw2} == "" ] 
then  
        echo -e "密码不能为空,请重新输入.\n" 
        read -p "请重复输入远端节点root密码（要求全部节点密码一致）：" nodepw2
fi

if [ ${nodepw1} == ${nodepw2} ] 
then 	
	#两次输入密码相同，则把密码写入到./nodepw
	echo ${nodepw2} > ./nodepw
else
	echo "两次输入密码不相同，请重新尝试！"
fi 


#调用ssh_truset.sh 设置其他节点ssh互信免密码。
bash ./ssh_truest.sh && echo -e "执行ssh_truesh.sh成功！\n"

#优化一下linux常用设置
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config &&  setenforce 0 &>/dev/null
if [ $? == 0 ] ;then echo -e "关闭 selinux 成功\n" ;fi 
systemctl stop firewalld  && systemctl disable firewalld
if [ $? == 0 ] ;then echo -e "关闭 firewalld 成功\n" ;fi 
systemctl stop NetworkManager  && systemctl disable NetworkManager
if [ $? == 0 ] ;then echo -e "关闭 NetworkManager 成功\n" ;fi 


#挂载两张光盘，下一步成功web yum源
umount /mnt
umount /var/www/html/dvd
umount /var/www/html/openstack

mkdir /var/www/html/dvd &>/dev/null
mkdir /var/www/html/openstack &>/dev/null


cat <<EOF >>/etc/fstab
/iso/rhel-server-7.1-x86_64-dvd.iso     /var/www/html/dvd       iso9660 defaults        0 0 
/iso/rhel-osp-6.0-2015-02-23.2-x86_64.iso     /var/www/html/openstack       iso9660 defaults        0 0 
EOF

mount -a 

if [ $? == 0 ] ;
then 
	echo -e "配置自动挂载点/iso/rhel-server-7.1-x86_64-dvd.iso--->/var/www/html/dvd  成功\n"
	echo -e "配置自动挂载点/iso/rhel-osp-6.0-2015-02-23.2-x86_64.iso--->/var/www/html/openstack  成功\n" 
fi 

#允许所有ip的客户端向本ntp服务器连接，并设置本地层数为10
sed -i "s/#allow.*/allow all/g" /etc/chrony.conf && sed -i "s/#local stratum 10/local stratum 10/g" /etc/chrony.conf

#重启ntp httpd 服务
systemctl enable chronyd && systemctl restart  chronyd
systemctl enable httpd && systemctl restart httpd

#备份cdrom.repo源
mv /etc/yum.repos.d/cdrom.repo /etc/yum.repos.d/cdrom.repo.bak
if [ $? == 0 ] ;then echo -e "备份dvd.repo yum源文件 成功\n" ;fi 

cat <<EOF >/etc/yum.repos.d/web.repo
[dvd]
name = dvd
baseurl = http://${ntpip}/dvd/
gpgcheck = 0
enabled = 1

[RH7-RHOS-6.0-Installer]
name = RH7-RHOS-6.0-Installer
baseurl = http://${ntpip}/openstack/RH7-RHOS-6.0-Installer/
gpgcheck = 0
enabled = 1

[RH7-RHOS-6.0]
name = RH7-RHOS-6.0
baseurl = http://${ntpip}/openstack/RH7-RHOS-6.0/
gpgcheck = 0
enabled = 1

[RHEL-7-RHSCL-1.2]
name = RHEL-7-RHSCL-1.2
baseurl = http://${ntpip}/openstack/RHEL-7-RHSCL-1.2/
gpgcheck = 0
enabled = 1

[RHEL7-Errata]
name = RHEL7-Errata
baseurl = http://${ntpip}/openstack/RHEL7-Errata/
gpgcheck = 0
enabled = 1
EOF

if [ $? == 0 ] ;then echo -e "创建web.repo yum源文件 成功\n" ;fi 

yum repolist && yum makecache 
if [ $? == 0 ] ;then echo -e "测试web.repo yum源可用\n" ;fi 


#清空远端节点的repo仓库源文件
ssh root@compute " rm -rf /etc/yum.repos.d/* " && echo -e "删除compute节点/etc/yum.repos.d/* 成功\n" 
ssh root@controller " rm -rf /etc/yum.repos.d/* " && echo -e "删除controller节点/etc/yum.repos.d/* 成功\n" 

#拷贝web.yum文件到远端节点
scp /etc/yum.repos.d/web.repo root@compute:/etc/yum.repos.d/ && echo -e " 拷贝/etc/yum.repos.d/web.repo到compute节点 成功\n" 
scp /etc/yum.repos.d/web.repo root@controller:/etc/yum.repos.d/ && echo -e " 拷贝/etc/yum.repos.d/web.repo到controller节点 成功\n" 

#拷贝hosts文件到远端节点
scp /etc/hosts root@compute:/etc/  && echo -e " 拷贝/etc/hosts到compute节点 成功\n" 
scp /etc/hosts root@controller:/etc/ && echo -e " 拷贝/etc/hosts到controller节点 成功\n" 

#拷贝ssh_truest文件到远端节点
scp ./ssh_truest.sh root@compute:/root/  && echo -e " 拷贝ssh_truest.sh到compute节点 成功\n" 
scp ./ssh_truest.sh root@controller:/root/ && echo -e " 拷贝ssh_truest.sh到controller节点 成功\n" 

#拷贝ssh_truest要用的密码文件nodepw到远端节点
scp ./nodepw root@compute:/root/  && echo -e " 拷贝nodepw到compute节点 成功\n" 
scp ./nodepw root@controller:/root/  && echo -e " 拷贝nodepw到controller节点 成功\n" 

#测试web源是否可用
ssh root@compute " yum repolist && yum makecache " && echo -e "web.repo在compute节点上可用\n"
ssh root@controller " yum repolist && yum makecache " && echo -e "web.repo在controller节点上可用\n"

#ssh远程给远端节点安装必要软件包
ssh root@compute " yum install -y lrzsz \
vim \
bash-completion \
net-tools \
openssl \
openssl-devel \
chrony.x86_64 \
zip \
unzip \
ntpdate \
telnet \
expect"

ssh root@controller " yum install -y lrzsz \
vim \
bash-completion \
net-tools \
openssl \
openssl-devel \
chrony.x86_64 \
zip \
unzip \
ntpdate \
telnet \
expect"

#修改ntp客户端配置信息，并打开相应服务。最后执行ssh互信脚本
ssh root@controller " 
sed -i \"/^server [1-3]/ s/^/#/\" /etc/chrony.conf 
sed -i \"s/server 0.rhel.pool.ntp.org iburst/server ntp iburst/\" /etc/chrony.conf 
systemctl enable chronyd && systemctl restart  chronyd
ntpdate ntp && echo -e \"cmpute节点的ntp服务正常\n\"
bash /root/ssh_truest.sh && echo -e \"controll节点设置ssh互信成功\n\"" 

ssh root@compute " 
sed -i \"/^server [1-3]/ s/^/#/\" /etc/chrony.conf 
sed -i \"s/server 0.rhel.pool.ntp.org iburst/server ntp iburst/\" /etc/chrony.conf
systemctl enable chronyd && systemctl restart  chronyd
ntpdate ntp && echo -e \"cmpute节点的ntp服务正常\n\"
bash /root/ssh_truest.sh && echo -e \"compute节点设置ssh互信成功\n\""

#在controller节点上操作，用packstack部署openstack
ssh root@controller "
yum install -y openstack-packstack.noarch 
rm -rf /root/pack* 
packstack --gen-answer-file=/root/packstack.txt"

#修改packstack应答文件
ssh root@controller  "
ntpip=`cat /etc/hosts |grep -v localhost |grep ntp |awk '{print $1}'`
conip=`cat /etc/hosts |grep -v localhost |grep controller |awk '{print $1}'`
comip=`cat /etc/hosts |grep -v localhost |grep compute |awk '{print $1}'`
sed -i "s/CONFIG_NTP_SERVERS=.*/CONFIG_NTP_SERVERS=\${ntpip}/g" /root/packstack.txt
sed -i "s/CONFIG_COMPUTE_HOSTS=.*/CONFIG_COMPUTE_HOSTS=\${comip},\${conip}/g" /root/packstack.txt   #控制节点及计算节点都参数nova运算
sed -i "s/CONFIG_PROVISION_DEMO=y/CONFIG_PROVISION_DEMO=n/g" /root/packstack.txt
sed -i "s/CONFIG_HORIZON_SSL=n/CONFIG_HORIZON_SSL=y/g" /root/packstack.txt
sed -i "s/CONFIG_HEAT_INSTALL=n/CONFIG_HEAT_INSTALL=y/g" /root/packstack.txt
sed -i "s/CONFIG_KEYSTONE_ADMIN_PW=.*/CONFIG_KEYSTONE_ADMIN_PW=adminh3c./g" /root/packstack.txt"


#根据应答文件，开始部署openstak
ssh  root@controller "packstack --answer-file=/root/packstack.txt"


