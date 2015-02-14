# Making a 1G disk on /dev/loop0
rm -f bigdisk
dd if=/dev/zero of=bigdisk bs=1 seek=1G count=0
losetup /dev/loop0 bigdisk
./xenvmd.native --daemon
./xenvm.native format /dev/loop0 --vg djstest --host 127.0.0.1
./xenvm.native open /dev/loop0 --host 127.0.0.1
LVS="free live masterJournal toLVM fromLVM"
for i in ${LVS}; do
  echo Creating $i
  ./xenvm.native create --lv $i --host 127.0.0.1
done
for i in ${LVS}; do
  echo Activating $i
  ./xenvm.native activate --lv $i --host 127.0.0.1
done

dd if=/dev/zero of=localJournal bs=1M count=1

echo Run 'sudo ./local-allocator.native' and type 'djstest-live' to request an allocation
echo Run 'sudo ./remote-allocator.native' to see the LVM updates being picked up
echo Run './cleanup.sh' to remove all volumes and devices
