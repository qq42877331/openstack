#!/bin/bash

nodepw=`cat ./nodepw `

#定义一个put_sshkey方法
put_sshkey(){
/usr/bin/expect -c "
        set timeout 10
        spawn ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa.pub root@$1
        expect {
            password: { send $2\r;interact; }
        
        }"
}

#生成本地ssh pubkey 
[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa


for i in `cat /etc/hosts |grep -v localhost | awk '{print $2}'`
do
	put_sshkey $i $nodepw
done
