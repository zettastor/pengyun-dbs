#!/usr/bin/env bash

#ps -ef | grep IndependentProcessManager |grep -v grep | awk '{print $2 " " $(NF-0)}'
a=`ps -ef | grep IndependentProcessManager | grep -v grep | awk '{print $2 " " $(NF-0)}' | grep -v group`
b=`ps -ef | grep IndependentProcessManager | grep group | grep -v grep |  awk '{print $2 " " $(NF-1)}'`

if [[ ! -n $a ]];then
echo >/dev/null 2>&1
else
echo "$a"
fi

if [[ ! -n $b ]]; then
echo >/dev/null 2>&1
else
echo "$b"
fi

