# IO Pacing Prototype

This folder contains files related to IO Pacing prototype in SPDK: configuration files, test scripts, results, etc.

## Test setup preparation

### Target

Clone and build SPDK.

~~~{.sh}
git clone https://github.com/Mellanox/spdk.git
cd spdk
git checkout io_pacing
git submodule update --init
./configure --with-rdma --prefix=$PWD/install-$HOSTNAME --disable-unit-tests
make
make install
~~~

### Initiator

Test scripts use fio with SPDK plugin as initiator. Fio and SPDK should be built on every client host separately to allow differences in environment. Below are steps to setup initiator hosts. Note, that clone should be done just once (if sources are on shared storage), while configure, make and install steps should be done on every initiator host.

#### Fio

~~~{.sh}
git clone https://github.com/axboe/fio
cd fio
git checkout fio-3.15
./configure --prefix=$PWD/install-$HOSTNAME
make
make install
cd ..
~~~

#### SPDK

SPDK for initiator host should be built right after fio build for the same host.

~~~{.sh}
git clone https://github.com/Mellanox/spdk.git
cd spdk
git checkout io_pacing
git submodule update --init
./configure --with-rdma --prefix=$PWD/install-$HOSTNAME --disable-unit-tests --with-fio=$PWD/../fio
make
make install
cp ./examples/nvme/fio_plugin/fio_plugin install-$HOSTNAME/lib
~~~

## Running tests

Test script is `test.sh`. You will also need job files for fio and target configration files. Job files can be found in `io_pacing/jobs` folder, target configs in `io_pacing/configs`. You may need to update some jobs and config parameters according to your setup. Also check test script for configurable parameters.

1. Start target

~~~{.sh}
sudo ./scripts/setup.sh
sudo hugeadm --pool-pages-min DEFAULT:4G
sudo neohost &
sudo ./install-$HOSTNAME/bin/spdk_tgt -c ./io_pacing/configs/nvmf_nvme.conf -m 0xFFFF
~~~

2. Run test script on one of the initiator hosts

~~~
$ ./test.sh
..........-..................!
Test parameters
Time        : 30
Read/write  : randread
Queue depth : 32
IO size     : 128k

Results
Host                           | kIOPS      | BW,Gb/s    | AVG_LAT,us      | Wire BW,Gb/s
-------------------------------|------------|------------|-----------------|----------------
r-dcs79                        | 87.9       | 92.1       | 363.1           |
spdk03.swx.labs.mlnx           | 87.7       | 91.9       | 364.4           |
-------------------------------|------------|------------|-----------------|----------------
Total                          | 175.6      | 184.1      |                 | 193.4409
~~~

## IO pacing methods

### Number of buffers limitation in SPDK

SPDK has a configuration parameter `NumSharedBuffers` that defines
number of data buffers (and size of buffer) to allocate for NVMf
transport. Buffers form a pool and are shared among all threads.

At start each thread allocates a number of buffers from common pool to
thread local cache. Size of the cache is controlled by `BufCacheSize`
configuration parameter.

When buffer is needed SPDK thread tries to allocate buffer from its
local cache. If there are no buffers it goes to common pool. If there
is nothing in common pool, IO request goes to pending buffer queue and
is retried when buffer is released by the same thread.

When buffer IO request is completed and buffer is not needed anymore,
SPDK tries to return it to local cache first. If local cache is full,
i.e. has length `BufCacheSize`, buffer is returned to common pool.

Data buffer pool is built on top of DPDK mempool API. It has its own
caching mechanism but we disable it in this PoC.

## Test setups

### Setup 1 - spdk-tgt-bw-03

**Target**: `spdk-tgt-bw-03` connected with 2 ports to switch sw-ceph02

**Disks**: 16 `INTEL SSDPE21D280GA`

**Initiator 1**: `r-dcs79` connected to switch sw-ceph02

**Initiator 2**: `spdk03` connected to switch sw-spdk01

### Setup 2 - swx-bw-07

**Target**: `swx-bw-07` connected with 2 ports to switch sw-spdk01

**Disks**: 16 `SAMSUNG MZWLL1T6HAJQ-00005`

**Initiator 1**: `spdk04` connected to switch sw-spdk01

**Initiator 2**: `spdk05` connected to switch sw-spdk01

## Results

Results for Samsung disks: [samsung_results.md](samsung_results.md)

Results for Intel disks write flow: [intel_write.md](intel_write.md)

Results for Intel disks small IOs: [intel_small.md](intel_small.md)

Results for Mixed disks: [mixed_results.md](mixed_results.md)

| Test #              | IO pacing            | Disks                   | Description                                  |
|---------------------|----------------------|-------------------------|----------------------------------------------|
| [Test 1](#test-1)   | none                 | 1 Null                  | Basic test                                   |
| [Test 2](#test-2)   | none                 | 16 Null                 | Basic test                                   |
| [Test 3](#test-3)   | none                 | 16 NVMe                 | Basic test                                   |
| [Test 4](#test-4)   | NumSharedBuffers     | 16 Null                 | Basic test                                   |
| [Test 5](#test-5)   | NumSharedBuffers     | 16 NVMe                 | Basic test                                   |
| [Test 6](#test-6)   | NumSharedBuffers     | 16 NVMe                 | Stability test: multiple same test runs      |
| [Test 7](#test-7)   | NumSharedBuffers     | 16 NVMe                 | Different number of target cores             |
| [Test 8](#test-8)   | NumSharedBuffers     | 16 NVMe                 | Different buffer cache size                  |
| [Test 9](#test-9)   | NumSharedBuffers     | 16 NVMe                 | Different number of buffers, 16 target cores |
| [Test 10](#test-10) | NumSharedBuffers     | 16 NVMe                 | Different number of buffers, 4 target cores  |
| [Test 11](#test-11) | NumSharedBuffers     | 16 NVMe, split 3, delay | No limit of IO depth for delay devices       |
| [Test 12](#test-12) | NumSharedBuffers     | 16 NVMe, split 3, delay | Control IO depth for delay devices           |
| [Test 13](#test-13) | N/A                  | 16 NVMe, split 3, delay | Test disk latencies                          |
| [Test 14](#test-14) | Rate based, adaptive | 16 NVMe                 | Basic test                                   |
| [Test 15](#test-15) | Rate based, fixed    | 16 NVMe                 | Basic test                                   |
| [Test 16](#test-16) | Rate based, adaptive | 16 NVMe, split 3, delay | Test 12 with IO pacer                        |
| [Test 18](#test-18) | Rate based, adaptive | 16 NVMe                 | Mixed IO sizes                               |

### Test 1

**IO pacing**: `none`

**Configuration**: `config_null_1`

**Initiator**: `fio+SPDK`

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 184.0      | 196.3107   | 90.5            | 1.5
16         | 184.6      | 196.3327   | 181.1           | .8
32         | 184.0      | 196.3318   | 364.0           | 2.4
64         | 177.3      | 188.6632   | 756.1           | .7
128        | 177.4      | 188.7209   | 1511.9          | .6
256        | 177.6      | 188.7393   | 3021.1          | .5
~~~

### Test 2

**IO pacing**: `none`

**Configuration**: `config_null_16`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----|-------|----------|-------------|-----------|-------------|
| 16  | 184.5 | 196.1237 | 181.3       | .5        | 99.1        |
| 32  | 184.8 | 196.333  | 362.5       | .1        | 91.0        |
| 36  | 184.8 | 196.3326 | 407.8       | .1        | 83.0        |
| 40  | 184.8 | 196.3322 | 453.2       | 0         | 88.3        |
| 44  | 184.8 | 196.3332 | 498.6       | .1        | 83.7        |
| 48  | 184.8 | 196.3331 | 543.9       | 0         | 90.4        |
| 64  | 184.8 | 196.3324 | 725.4       | 0         | 83.6        |
| 128 | 184.8 | 196.3335 | 1451.4      | .1        | 70.5        |
| 256 | 184.8 | 196.3331 | 2903.6      | .1        | 45.1        |

**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 184.8      | 196.331    | 179.8           | .2
| 4          | 184.8      | 196.3365   | 361.2           | .2
| 8          | 182.4      | 193.8894   | 733.8           | .2
| 16         | 179.1      | 190.5807   | 1496.6          | .2
| 32         | 181.5      | 192.7129   | 2956.1          | .3
~~~

### Test 3

**IO pacing**: `none`

**Configuration**: `config_nvme`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------|-------|----------|-------------|-----------|-------------|----------------------|
| 32   | 184.7 | 196.333  | 362.8       | .4        | 97.1        | 62.3 (7.7)           |
| 36   | 184.7 | 196.3339 | 408.2       | .3        | 93.9        | 68.6 (8.5)           |
| 40   | 184.6 | 196.3309 | 453.7       | .3        | 93.5        | 78.0 (9.7)           |
| 44   | 182.7 | 196.0504 | 504.4       | 1.2       | 81.8        | 86.3 (10.7)          |
| 48   | 177.5 | 187.658  | 566.5       | 1.6       | 77.5        | 93.6 (11.7)          |
| 64   | 167.8 | 179.6868 | 799.0       | 2.7       | 73.3        | 123.3 (15.4)         |
| 128  | 162.2 | 180.4201 | 1653.7      | 5.0       | 73.2        | 253.0 (31.6)         |
| 256  | 152.7 | 176.4986 | 3514.7      | 5.0       | 74.5        | 500.0 (62.5)         |
| 1024 | 136.6 | 159.2902 | 14241.0     | 6.9       | 63.4        | 933.0 (116.6)        |
| 2048 | 134.8 | 157.7392 | 19880.3     | 8.8       | 68.7        | 1277.0 (159.6)       |

**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 164.3      | 175.335    | 202.4           | .2
| 4          | 184.8      | 196.3352   | 361.3           | .2
| 8          | 107.4      | 113.4529   | 1247.9          | .2
| 16         | 104.3      | 110.5348   | 2571.3          | .3
| 32         | 104.5      | 110.9826   | 5133.0          | .2
~~~

### Test 4

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 config_null_16`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----|-------|----------|-------------|-----------|-------------|
| 16  | 184.6 | 196.1118 | 181.3       | .3        | 99.1        |
| 32  | 184.8 | 196.3311 | 362.6       | .3        | 97.0        |
| 36  | 184.8 | 196.3328 | 407.9       | .2        | 94.0        |
| 40  | 184.8 | 196.3331 | 453.2       | 0         | 95.5        |
| 44  | 184.8 | 196.3322 | 498.6       | .1        | 95.3        |
| 48  | 184.8 | 196.3332 | 543.9       | 0         | 95.0        |
| 64  | 184.7 | 196.3331 | 725.8       | .3        | 95.0        |
| 128 | 184.8 | 196.3329 | 1451.6      | .1        | 92.3        |
| 256 | 184.8 | 196.3301 | 2903.8      | .1        | 96.1        |

**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 184.8      | 196.3326   | 179.8           | .2
| 4          | 184.8      | 196.3337   | 361.3           | .2
| 8          | 184.8      | 196.3349   | 724.2           | .2
| 16         | 184.8      | 196.3341   | 1450.1          | .2
| 32         | 184.8      | 196.3341   | 2901.9          | .2
~~~

### Test 5

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme`

**Initiator**: `fio+SPDK`

**Target CPU mask:** 0xF

| QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------|-------|----------|-------------|-----------|-------------|----------------------|
| 32   | 184.7 | 196.3081 | 362.7       | .2        | 99.3        | 59.6 (7.4)           |
| 64   | 184.4 | 196.3301 | 727.0       | .6        | 90.6        | 89.6 (11.2)          |
| 128  | 184.5 | 196.3342 | 1454.3      | .4        | 90.5        | 91.3 (11.4)          |
| 256  | 184.5 | 196.3295 | 2908.7      | .4        | 90.1        | 91.3 (11.4)          |
| 1024 | 184.2 | 196.3299 | 11654.3     | .5        | 89.7        | 94.0 (11.7)          |
| 2048 | 184.1 | 196.3253 | 21264.3     | 1.2       | 89.8        | 95.0 (11.8)          |

**Initiator**: `fio+kernel 8 jobs`

**Target CPU mask:** 0xFFFF

~~~
| QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
| 2          | 165.4      | 175.6145   | 201.1           | .2
| 4          | 184.8      | 196.3025   | 361.3           | .2
| 8          | 184.8      | 196.2741   | 724.5           | .2
| 16         | 184.8      | 196.3269   | 1450.3          | .2
| 32         | 184.8      | 196.3037   | 2903.2          | .3
~~~

### Test 6

Stability tests. Check variation of results between multiple runs for
different queue depths.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=6 config_nvme`

**Initiator**: `fio+SPDK`

| QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|------|-------|----------|-------------|-----------|-------------|
| 32   | 184.7 | 196.3127 | 362.7       | .4        | 99.4        |
| 32   | 184.8 | 196.3116 | 362.5       | .1        | 99.1        |
| 32   | 184.8 | 196.3224 | 362.5       | 0         | 99.4        |
| 32   | 184.8 | 196.3193 | 362.6       | .2        | 99.4        |
| 32   | 184.8 | 196.3207 | 362.6       | .2        | 99.2        |
| 32   | 184.8 | 196.3202 | 362.6       | .3        | 99.3        |
| 32   | 184.8 | 196.3186 | 362.6       | .2        | 99.4        |
| 32   | 184.7 | 196.319  | 362.7       | .3        | 99.2        |
| 32   | 184.8 | 196.31   | 362.5       | .1        | 99.3        |
| 32   | 184.8 | 196.3194 | 362.6       | .2        | 99.4        |
| 256  | 184.7 | 196.3318 | 2905.8      | .3        | 90.8        |
| 256  | 184.6 | 196.331  | 2906.4      | .4        | 89.4        |
| 256  | 184.6 | 196.3302 | 2906.6      | .3        | 89.3        |
| 256  | 184.6 | 196.328  | 2907.3      | .4        | 89.2        |
| 256  | 184.6 | 196.3333 | 2906.3      | .3        | 91.0        |
| 256  | 184.6 | 196.3318 | 2906.7      | .3        | 89.8        |
| 256  | 184.6 | 196.3309 | 2906.9      | .3        | 90.3        |
| 256  | 184.7 | 196.3312 | 2906.0      | .2        | 90.6        |
| 256  | 184.7 | 196.3424 | 2906.0      | .3        | 89.5        |
| 256  | 184.7 | 196.3308 | 2906.1      | .3        | 90.0        |
| 1024 | 184.5 | 196.323  | 11639.8     | .4        | 88.7        |
| 1024 | 184.5 | 196.3303 | 11638.0     | .5        | 87.8        |
| 1024 | 184.5 | 196.2538 | 11639.6     | .5        | 88.2        |
| 1024 | 184.5 | 196.3264 | 11639.5     | .5        | 88.0        |
| 1024 | 184.4 | 196.3148 | 11642.0     | .5        | 88.5        |
| 1024 | 184.5 | 196.3287 | 11637.4     | .5        | 87.8        |
| 1024 | 184.5 | 196.3236 | 11638.4     | .5        | 88.4        |
| 1024 | 184.4 | 196.3291 | 11640.6     | .4        | 89.3        |
| 1024 | 184.5 | 196.3237 | 11639.2     | .4        | 88.4        |
| 1024 | 184.4 | 196.3293 | 11640.4     | .5        | 87.8        |
| 2048 | 184.1 | 196.3099 | 23322.6     | 1.2       | 87.0        |
| 2048 | 184.3 | 196.3222 | 22865.1     | 1.1       | 88.6        |
| 2048 | 184.2 | 196.3225 | 21973.9     | 1.1       | 88.2        |
| 2048 | 184.2 | 196.3202 | 22456.9     | 1.3       | 87.9        |
| 2048 | 184.2 | 196.3208 | 22160.7     | 1.0       | 87.8        |
| 2048 | 184.2 | 196.3207 | 22533.7     | .9        | 87.6        |
| 2048 | 184.2 | 196.3194 | 22282.5     | 1.2       | 88.5        |
| 2048 | 184.2 | 196.3175 | 22542.9     | 1.3       | 88.5        |
| 2048 | 184.2 | 196.3023 | 23316.1     | 1.2       | 88.4        |
| 2048 | 184.2 | 196.3171 | 22966.5     | 1.1       | 88.0        |

### Test 7

Check performance effect of number of target cores.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=$((num_buffers/num_cores)) config_nvme`

**Initiator**: `fio+SPDK`

Target cores 16 (0xFFFF). Buffer cache size 6

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 97.3       | 106.0621   | 171.7           | 5.9
16         | 162.1      | 176.1584   | 206.3           | 10.2
32         | 177.0      | 192.845    | 378.5           | 10.1
64         | 181.2      | 193.9438   | 740.0           | 5.9
128        | 181.8      | 195.2145   | 1475.2          | 4.6
256        | 182.4      | 195.8669   | 2942.2          | 4.0
~~~

Target cores 8 (0xFF). Buffer cache size 12

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 104.5      | 110.949    | 159.8           | 0
16         | 174.7      | 185.6216   | 191.4           | 2.1
32         | 184.8      | 196.2932   | 362.4           | 0
64         | 184.7      | 196.298    | 725.8           | .2
128        | 184.8      | 196.3279   | 1451.8          | .1
256        | 184.7      | 196.3195   | 2905.4          | .2
~~~

Target cores 4 (0xF). Buffer cache size 24

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 106.4      | 113.1102   | 157.0           | .1
16         | 174.4      | 185.751    | 191.7           | .2
32         | 184.8      | 196.3121   | 362.4           | 0
64         | 184.8      | 196.3286   | 725.6           | .1
128        | 184.8      | 196.3073   | 1451.9          | .1
256        | 184.8      | 196.3337   | 2904.5          | .1
~~~

Target cores 2 (0x3). Buffer cache size 48

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 109.5      | 116.4625   | 152.5           | .1
16         | 171.7      | 182.089    | 194.7           | .3
32         | 184.7      | 196.2224   | 362.6           | 0
64         | 184.8      | 196.3316   | 725.6           | .1
128        | 184.8      | 196.3326   | 1451.6          | .1
256        | 184.8      | 196.3332   | 2903.9          | .1
~~~

Target cores 1 (0x1). Buffer cache size 96

~~~
QD         | BW         | WIRE BW    | AVG LAT, us     | BW STDDEV
8          | 101.8      | 108.2169   | 164.1           | .1
16         | 150.8      | 160.8635   | 221.9           | .3
32         | 177.8      | 188.5567   | 376.8           | .3
64         | 177.6      | 188.2296   | 755.1           | .5
128        | 171.7      | 182.3304   | 1562.2          | .5
256        | 156.9      | 166.5067   | 3420.7          | .6
~~~

### Test 8

Check performance effects of buffer cache size.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=$buf_cache_size config_nvme`

**Initiator**: `fio+SPDK`

Buffer cache size 6.

~~~
QD         | BW         | WIRE BW
8          | 96.1       | 101.7948
16         | 167.9      | 179.8046
32         | 182.3      | 193.8036
64         | 182.7      | 194.3911
128        | 182.8      | 195.7273
256        | 183.1      | 194.1423
~~~

Buffer cache size 0.

~~~
QD         | BW         | WIRE BW
8          | 94.5       | 100.5522
16         | 166.9      | 178.6776
32         | 182.1      | 193.7545
64         | 182.7      | 194.8118
~~~

Test hangs with queue depth 128 and more. One of initiators can not
connect all the QPs. Probably, without cache it is possible that some
threads will never get buffers and will not be able to handle even
admin commands.

Buffer cache size 1.

~~~
QD         | BW         | WIRE BW
8          | 91.9       | 98.8753
16         | 163.2      | 176.9629
32         | 182.1      | 194.0412
64         | 182.6      | 194.3561
128        | 133.0      | 139.5647
256        | 134.5      | 137.4158
~~~

With very small buffer cache it works but we see performance
degradation with deep queues. Likely because of the same effect, some
threads consume all the buffers and others don't get enough to perform
well.

### Test 9

Check performance effect of number of data buffers. All buffers are
shared equally between all threads at start with `BufCacheSize`
parameter.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/16)) config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xFFFF

| Num buffers | Buf cache | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------|-----|-------|----------|-------------|-----------|-------------|
| 128         | 8         | 256 | 161.6 | 194.9704 | 3320.5      | 6.2       | 89.2        |
| 96          | 6         | 256 | 167.3 | 195.9908 | 3206.9      | 11.4      | 99.5        |
| 64          | 4         | 256 | 156.5 | 195.1129 | 3579.2      | 13.4      | 99.6        |
| 48          | 3         | 256 | 176.6 | 194.4154 | 3039.1      | 7.3       | 99.6        |
| 44          | 2         | 256 | 156.3 | 194.5452 | 3433.5      | 12.1      | 99.6        |
| 40          | 2         | 256 | 157.0 | 194.8172 | 3419.0      | 11.0      | 99.6        |
| 36          | 2         | 256 | 176.5 | 194.4009 | 3040.8      | 6.8       | 99.6        |
| 32          | 2         | 256 | 171.1 | 185.0244 | 3136.0      | 8.3       | 99.6        |
| 24          | 1         | 256 | 144.7 | 155.9214 | 3709.2      | 3.6       | 99.6        |
| 16          | 1         | 256 | 112.2 | 126.1672 | 4784.2      | 6.9       | 99.6        |


### Test 10

Check performance effect of number of data buffers with 4 cores. All
buffers are shared equally between all threads at start with
`BufCacheSize` parameter.

**IO pacing**: `Limit number of SPDK buffers to 96`

**Configuration**: `NUM_SHARED_BUFFERS=$num_buffers BUF_CACHE_SIZE=$((num_buffers/4)) config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

| Num buffers | Buf cache | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|-------------|-----------|------|-------|----------|-------------|-----------|-------------|----------------------|
| 128         | 32        | 256  | 176.6 | 191.0384 | 3038.0      | 1.8       | 79.0        | 102.6 (12.8)         |
| 128         | 32        | 1024 | 153.7 | 178.4195 | 13541.1     | 9.5       | 75.7        | 111.3 (13.9)         |
| 96          | 24        | 256  | 184.5 | 196.329  | 2908.5      | .3        | 89.5        | 91.0 (11.3)          |
| 96          | 24        | 1024 | 184.2 | 196.317  | 11654.3     | .5        | 88.5        | 95.6 (11.9)          |
| 64          | 16        | 256  | 184.8 | 196.324  | 2904.0      | .1        | 99.5        | 62.0 (7.7)           |
| 64          | 16        | 1024 | 77.4  | 157.1605 | 29278.3     | 28.3      | 98.0        | 57.3 (7.1)           |
| 48          | 12        | 256  | 184.7 | 196.2684 | 2906.1      | .2        | 99.5        | 43.3 (5.4)           |
| 48          | 12        | 1024 | 184.5 | 196.1051 | 11640.6     | .2        | 99.5        | 41.6 (5.2)           |
| 44          | 11        | 256  | 172.3 | 196.2197 | 3114.4      | 7.1       | 99.5        | 40.0 (5.0)           |
| 44          | 11        | 1024 | 175.2 | 195.7898 | 12259.3     | 8.2       | 99.5        | 38.3 (4.7)           |
| 40          | 10        | 256  | 184.4 | 195.948  | 2910.4      | .1        | 99.5        | 38.3 (4.7)           |
| 40          | 10        | 1024 | 170.6 | 195.2709 | 12590.4     | 3.5       | 99.5        | 33.0 (4.1)           |
| 36          | 9         | 256  | 174.0 | 195.4031 | 3084.8      | 5.8       | 99.5        | 34.0 (4.2)           |
| 36          | 9         | 1024 | 175.7 | 192.7424 | 12233.8     | .9        | 99.5        | 29.0 (3.6)           |
| 32          | 8         | 256  | 181.0 | 192.3175 | 2965.5      | .3        | 99.5        | 29.6 (3.7)           |
| 32          | 8         | 1024 | 174.1 | 185.2337 | 12338.3     | .6        | 99.5        | 25.6 (3.2)           |
| 24          | 6         | 256  | 156.1 | 166.2031 | 3438.5      | .5        | 99.6        | 21.3 (2.6)           |
| 24          | 6         | 1024 | 149.3 | 158.9107 | 14384.8     | 1.1       | 99.5        | 20.0 (2.5)           |
| 16          | 4         | 256  | 115.4 | 122.4798 | 4648.1      | .2        | 99.5        | 14.6 (1.8)           |
| 16          | 4         | 1024 | 109.7 | 115.9732 | 19572.2     | .7        | 99.5        | 14.0 (1.7)           |


Something strange is happening around 64 buffers with queue depth
of 1024. It is very unstable and numers are really low. Here is a
closer look with 3 runs for each.

| Num buffers | Buf cache | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------|------|-------|----------|-------------|-----------|-------------|
| 96          | 24        | 1024 | 184.5 | 196.3218 | 11636.1     | .4        | 88.0        |
| 96          | 24        | 1024 | 184.4 | 196.3181 | 11641.0     | .5        | 89.1        |
| 96          | 24        | 1024 | 184.5 | 196.3224 | 11639.6     | .5        | 88.4        |
| 80          | 20        | 1024 | 73.4  | 0        | 29277.6     | 28.4      | 99.4        |
| 80          | 20        | 1024 | 101.0 | 196.3324 | 22017.4     | 22.3      | 99.1        |
| 80          | 20        | 1024 | 74.0  | 0        | 29040.4     | 26.0      | 97.9        |
| 64          | 16        | 1024 | 131.7 | 30.8655  | 16737.7     | 17.3      | 99.4        |
| 64          | 16        | 1024 | 101.9 | 85.8252  | 22388.4     | 21.6      | 98.6        |
| 64          | 16        | 1024 | 134.4 | 77.1212  | 16298.1     | 14.4      | 98.8        |
| 56          | 14        | 1024 | 173.5 | 0        | 12379.3     | 5.8       | 99.5        |
| 56          | 14        | 1024 | 177.4 | 196.3213 | 12102.3     | 10.1      | 99.5        |
| 56          | 14        | 1024 | 168.7 | 0        | 12967.1     | 10.2      | 99.4        |
| 48          | 12        | 1024 | 184.6 | 196.2486 | 11634.9     | .1        | 99.5        |
| 48          | 12        | 1024 | 184.6 | 196.2123 | 11633.4     | .1        | 99.5        |
| 48          | 12        | 1024 | 184.6 | 196.255  | 11635.8     | .1        | 99.5        |

### Test 11

Split each NVMe disk into 3 partitions with SPDK split block device
and build delay block device on top of some partitions.

IO depth is shared equally between all disks. FIO runs 3 jobs with
queue depth of 85 or 341 each. This gives us total IO depth of 255 and
1023 per initiator respectively.

**IO pacing**: `Number of buffers`

**Configuration**: `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

| Num buffers | Num delay bdevs | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|-------------|-----------------|-----|-------|----------|-------------|-----------|-------------|----------------------|
| 96          | 0               | 85  | 181.9 | 193.1907 | 2939.0      | .6        | 93.5        | 93.6 (11.7)          |
| 96          | 0               | 341 | 179.3 | 194.0893 | 11966.7     | 1.8       | 93.6        | 95.0 (11.8)          |
| 96          | 16              | 85  | 184.0 | 195.7565 | 2988.2      | .1        | 93.4        | 89.0 (11.1)          |
| 96          | 16              | 341 | 179.3 | 190.1234 | 12368.2     | .3        | 92.2        | 91.6 (11.4)          |
| 96          | 32              | 85  | 139.0 | 145.6064 | 4052.0      | 2.4       | 89.1        | 89.0 (11.1)          |
| 96          | 32              | 341 | 124.5 | 127.9649 | 17376.1     | 2.5       | 86.6        | 94.3 (11.7)          |
| 48          | 0               | 85  | 184.5 | 196.2425 | 2974.9      | 1.1       | 99.5        | 47.3 (5.9)           |
| 48          | 0               | 341 | 175.7 | 196.0569 | 12306.1     | 2.5       | 99.4        | 45.6 (5.7)           |
| 48          | 16              | 85  | 135.8 | 141.2414 | 4363.3      | 3.2       | 99.4        | 47.3 (5.9)           |
| 48          | 16              | 341 | 111.3 | 113.8428 | 19482.0     | 3.1       | 99.3        | 44.0 (5.5)           |
| 48          | 32              | 85  | 89.6  | 93.682   | 6943.0      | 2.2       | 99.3        | 47.0 (5.8)           |
| 48          | 32              | 341 | 66.7  | 67.6684  | 32658.4     | 2.1       | 99.1        | 43.0 (5.3)           |

### Test 12

Split each NVMe disk into 3 partitions with SPDK split block device
and build delay block device on top of some partitions.

FIO runs 3 jobs with 16 disks each. Job 1 is always delay devices, job
2 may be good (16 delay bdevs) or delay (32 dely bdevs), job 3 is
always good. IO depth is fixed to 256 or 1024 for job 3. For jobs 1
and 2 it is set to value in QD column in the table below. For 32 delay
bdevs effective IO depth is twice the QD since we have 2 jobs each
with it's own IO depth.

**IO pacing**: `Number of buffers`

**Configuration**: `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

Job 3 QD is 256.

| Num buffers | Num delay bdevs | QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------------|----|-------|----------|-------------|-----------|-------------|
| 48          | 16              | 1  | 184.6 | 196.2039 | 2929.3      | .1        | 99.5        |
| 48          | 16              | 2  | 184.5 | 196.1547 | 2954.4      | .2        | 99.5        |
| 48          | 16              | 4  | 184.4 | 195.9771 | 3000.7      | 0         | 99.5        |
| 48          | 16              | 8  | 183.8 | 195.504  | 3102.0      | .1        | 99.5        |
| 48          | 16              | 16 | 181.5 | 193.2384 | 3326.9      | .1        | 99.5        |
| 48          | 16              | 32 | 171.7 | 181.3755 | 4023.0      | .8        | 99.5        |
| 48          | 32              | 1  | 184.6 | 196.0657 | 2930.6      | .1        | 99.5        |
| 48          | 32              | 2  | 184.5 | 196.0089 | 2954.2      | .1        | 99.5        |
| 48          | 32              | 4  | 184.1 | 195.4684 | 3006.6      | 0         | 99.5        |
| 48          | 32              | 8  | 181.5 | 192.3983 | 3142.1      | .1        | 99.5        |
| 48          | 32              | 16 | 171.0 | 181.6819 | 3531.1      | .5        | 99.5        |

Job 3 QD is 1024

| Num buffers | Num delay bdevs | QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-------------|-----------------|----|-------|----------|-------------|-----------|-------------|
| 48          | 16              | 1  | 184.2 | 195.8731 | 11678.7     | .1        | 99.5        |
| 48          | 16              | 2  | 184.2 | 195.6442 | 11704.4     | .1        | 99.5        |
| 48          | 16              | 4  | 184.0 | 195.4774 | 11762.4     | .2        | 99.5        |
| 48          | 16              | 8  | 183.4 | 194.7805 | 11889.7     | .2        | 99.5        |
| 48          | 16              | 16 | 182.3 | 192.9675 | 12146.8     | .5        | 99.5        |
| 48          | 16              | 32 | 176.0 | 187.1557 | 13353.8     | 1.1       | 99.4        |
| 48          | 16              | 64 | 155.7 | 170.9021 | 15523.1     | 1.0       | 99.4        |
| 48          | 32              | 1  | 183.8 | 195.8345 | 11702.7     | .7        | 99.5        |
| 48          | 32              | 2  | 184.0 | 195.576  | 11717.9     | .1        | 99.5        |
| 48          | 32              | 4  | 183.8 | 195.586  | 11772.1     | .2        | 99.5        |
| 48          | 32              | 8  | 182.8 | 194.0948 | 11929.1     | .3        | 99.5        |
| 48          | 32              | 16 | 179.0 | 189.0024 | 12372.0     | .6        | 99.4        |
| 48          | 32              | 32 | 160.3 | 168.7374 | 14232.4     | 1.7       | 99.4        |
| 48          | 32              | 64 | 138.2 | 144.7699 | 17425.0     | 4.2       | 99.4        |


### Test 13

Test latencies with different configurations.

**IO pacing**: `N/A`

**Configuration**: `config_null_16`, `config_nvme`, `config_nvme_split3_delay`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF

One initiator: spdk03

16 Null disks

| QD | BW   | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|------|---------|-------------|-----------|-------------|
| 1  | 50.8 | 53.6049 | 20.3        | .3        | 99.0        |
| 1  | 50.9 | 53.6818 | 20.3        | .3        | 99.0        |
| 1  | 50.1 | 52.8107 | 20.6        | .4        | 99.1        |
| 1  | 50.8 | 53.5558 | 20.3        | .3        | 99.1        |
| 1  | 50.7 | 53.5645 | 20.4        | .3        | 99.0        |

Local single NVMe disk (SPDK perf)

| QD | BW | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|----|---------|-------------|-----------|-------------|
| 1  | 11 |         | 87.51       |           |             |

16 NVMe disks

| QD  | BW   | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|-----|------|---------|-------------|-----------|-------------|
| 1   | 8.5  | 9.0731  | 122.3       | 0         | 98.8        |
| 1   | 8.5  | 9.0599  | 122.4       | 0         | 98.8        |
| 1   | 8.5  | 9.0664  | 122.4       | 0         | 98.9        |
| 1   | 8.5  | 9.0549  | 122.3       | 0         | 98.8        |
| 1   | 8.5  | 9.0622  | 122.4       | 0         | 98.9        |

48 split disks (1 job)

| QD | BW  | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|-----|---------|-------------|-----------|-------------|
| 1  | 8.2 | 8.6961  | 127.5       | 0         | 99.0        |
| 1  | 8.2 | 8.7048  | 127.3       | 0         | 99.1        |
| 1  | 8.2 | 8.7198  | 127.2       | 0         | 99.0        |
| 1  | 8.2 | 8.7214  | 127.0       | 0         | 99.0        |
| 1  | 8.2 | 8.7181  | 127.2       | 0         | 99.0        |

48 split+delay disks (1 job)

| QD | BW | WIRE BW | AVG LAT, us | BW STDDEV | L3 Hit Rate |
|----|----|---------|-------------|-----------|-------------|
| 1  | .9 | 0.9805  | 1136.2      | 0         | 98.4        |
| 1  | .9 | 0.9805  | 1136.0      | 0         | 98.4        |
| 1  | .9 | 0.9805  | 1136.1      | 0         | 98.6        |
| 1  | .9 | 0.9805  | 1135.7      | 0         | 98.5        |
| 1  | .9 | 0.9805  | 1135.9      | 0         | 98.4        |

### Test 14

Basic test with rate based IO pacing. Adaptive rate IO pacer. FIO with 8 jobs.

**IO pacing**: `Rate based`

**Configuration**: `config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF0 (4 cores)

Adaptive mechanism works as follows. IO pacer measures average IO
period, i.e. how often IOs leave the pacer and go to buffer allocation
and disk. Every tuning period (10 ms) pacer period is adjusted to
match the measured IO period minus 1 us. Adjustments to pacer period
are done in steps (1 us). For example, if current pacer period is 25
us and measured IO period is 35 us, pacer period will be set to 26
us. This works in both directions, up and down. Adjustments to pacer
period are limited by a range with lower bound being the configured
pacer period value (the first column in the table below) and upper
bound being twice the lower bound.

| Pacer period, us | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------------------|------|-------|----------|-------------|-----------|-------------|----------------------|
| 5.6 (22.4)       | 256  | 129.0 | 118.9491 | 4159.1      | 1.2       | 87.6        | 257.3 (32.1)         |
| 5.6 (22.4)       | 1024 | 116.7 | 126.7461 | 17978.0     | 1.2       | 99.4        | 1026.3 (128.2)       |
| 5.6 (22.4)       | 2048 | 119.2 | 138.0614 | 35387.6     | 1.4       | 63.2        | 1037.0 (129.6)       |
| 5.65 (22.6)      | 256  | 129.7 | 124.9634 | 4136.2      | 1.3       | 92.9        | 98.3 (12.2)          |
| 5.65 (22.6)      | 1024 | 119.3 | 110.5019 | 17997.6     | 1.2       | 50.6        | 684.6 (85.5)         |
| 5.65 (22.6)      | 2048 | 120.4 | 111.7765 | 34830.7     | 1.5       | 50.8        | 1088.6 (136.0)       |
| 5.675 (22.7)     | 256  | 174.6 | 195.3761 | 3073.1      | 1.3       | 53.8        | 27.6 (3.4)           |
| 5.675 (22.7)     | 1024 | 130.7 | 115.8018 | 16421.1     | 1.8       | 52.5        | 1025.0 (128.1)       |
| 5.675 (22.7)     | 2048 | 156.5 | 195.073  | 27471.3     | 1.9       | 99.3        | 27.3 (3.4)           |
| 5.7 (22.8)       | 256  | 183.0 | 194.6647 | 2932.2      | 0         | 99.5        | 25.6 (3.2)           |
| 5.7 (22.8)       | 1024 | 159.8 | 185.5446 | 13439.6     | 2.0       | 99.4        | 36.0 (4.5)           |
| 5.7 (22.8)       | 2048 | 182.7 | 194.1884 | 23501.3     | 0         | 99.3        | 27.0 (3.3)           |
| 5.725 (22.9)     | 256  | 182.3 | 193.7391 | 2944.4      | 0         | 99.5        | 25.6 (3.2)           |
| 5.725 (22.9)     | 1024 | 182.1 | 193.4434 | 11791.5     | 0         | 99.4        | 25.6 (3.2)           |
| 5.725 (22.9)     | 2048 | 169.2 | 193.2842 | 25395.9     | 1.3       | 99.1        | 32.3 (4.0)           |
| 5.75 (23)        | 256  | 181.5 | 192.9044 | 2957.2      | 0         | 99.5        | 24.3 (3.0)           |
| 5.75 (23)        | 1024 | 181.3 | 192.6004 | 11839.8     | 0         | 99.4        | 26.6 (3.3)           |
| 5.75 (23)        | 2048 | 173.6 | 192.5688 | 24150.8     | .7        | 99.0        | 30.0 (3.7)           |
| 5.775 (23.1)     | 256  | 180.7 | 192.1829 | 2969.0      | 0         | 99.5        | 25.0 (3.1)           |
| 5.775 (23.1)     | 1024 | 171.1 | 191.9538 | 12370.6     | .8        | 66.7        | 26.3 (3.2)           |
| 5.775 (23.1)     | 2048 | 176.6 | 191.7225 | 23859.1     | 0         | 99.3        | 32.0 (4.0)           |
| 5.8 (23.2)       | 256  | 179.9 | 191.2576 | 2982.5      | 0         | 99.5        | 24.3 (3.0)           |
| 5.8 (23.2)       | 1024 | 179.8 | 191.0265 | 11943.7     | 0         | 99.4        | 24.0 (3.0)           |
| 5.8 (23.2)       | 2048 | 179.7 | 190.9277 | 23895.5     | 0         | 99.4        | 28.0 (3.5)           |
| 6 (24)           | 256  | 174.2 | 185.1402 | 3081.3      | .1        | 99.5        | 23.0 (2.8)           |
| 6 (24)           | 1024 | 174.0 | 184.9201 | 12338.7     | 0         | 99.5        | 22.3 (2.7)           |
| 6 (24)           | 2048 | 174.0 | 184.6929 | 24680.9     | .1        | 99.4        | 22.3 (2.7)           |

**Detailed NVMf target statistics**

**CPU mask**: 0xF0 (4 cores)

| Pacer period, us | QD  | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) |
|------------------|-----|-------|----------|-------------|-----------|-------------|----------------------|
| 5.7 (22.8)       | 256 | 166.1 | 194.3685 | 25902.5     | 1.7       | 99.3        | 27.3 (3.4)           |

~~~
CPU mask 0xF0, num cores 4, IO pacer period 5700, adjusted period 22800
Bdev avg read lat, us: 247.819538
Poll group: "nvmf_tgt_poll_group_4"
  Pacer calls, polls, ios: 5158146, 1674906, 1643446
  Pacer poll, io period, us: 25.026 25.505
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 5158146, 1715921, 857960
    Comps/poll: .332
    Req lat, us: 4130.835
    Req lat (total), us: 3728.752
    Req states 1: [3584,0,509,0,0,0,0,2,0,0,0,1,0,0]
    Req states 2: [3585,0,509,0,0,0,0,0,0,0,0,2,0,0]
    Req states 3: [3585,0,508,0,0,0,0,1,0,0,0,2,0,0]
    Req lat 1, us: 3291.641
    Req lat 2, us: 5243.603
    Req lat 3, us: 3867.714
  Device: "mlx5_1"
    Polls, comps, reqs: 5158146, 1570970, 785485
    Comps/poll: .304
    Req lat, us: 3997.106
    Req lat (total), us: 3762.826
    Req states 1: [3584,0,508,0,0,0,0,2,0,0,0,2,0,0]
    Req states 2: [3584,0,505,0,0,0,0,4,0,0,0,3,0,0]
    Req states 3: [3584,0,508,0,0,0,0,3,0,0,0,1,0,0]
    Req lat 1, us: 2260.442
    Req lat 2, us: 4880.427
    Req lat 3, us: 3465.314
Poll group: "nvmf_tgt_poll_group_5"
  Pacer calls, polls, ios: 4612768, 1685853, 1643446
  Pacer poll, io period, us: 24.863 25.505
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 4612768, 1715941, 857970
    Comps/poll: .371
    Req lat, us: 342.025
    Req lat (total), us: 592.427
    Req states 1: [4090,0,1,0,0,0,0,5,0,0,0,0,0,0]
    Req states 2: [4091,0,2,0,0,0,0,2,0,0,0,1,0,0]
    Req states 3: [4091,0,1,0,0,0,0,4,0,0,0,0,0,0]
    Req lat 1, us: 1202.860
    Req lat 2, us: 801.954
    Req lat 3, us: 612.220
  Device: "mlx5_1"
    Polls, comps, reqs: 4612768, 1570968, 785484
    Comps/poll: .340
    Req lat, us: 642.176
    Req lat (total), us: 476.522
    Req states 1: [4092,0,2,0,0,0,0,1,0,0,0,1,0,0]
    Req states 2: [4092,0,0,0,0,0,0,3,0,0,0,1,0,0]
    Req states 3: [4092,0,1,0,0,0,0,3,0,0,0,0,0,0]
    Req lat 1, us: 110.647
    Req lat 2, us: 644.583
    Req lat 3, us: 479.246
Poll group: "nvmf_tgt_poll_group_6"
  Pacer calls, polls, ios: 2967952, 1688370, 1654105
  Pacer poll, io period, us: 24.826 25.340
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 2967952, 1726312, 863156
    Comps/poll: .581
    Req lat, us: 4122.330
    Req lat (total), us: 3984.763
    Req states 1: [3584,0,510,0,0,0,0,2,0,0,0,0,0,0]
    Req states 2: [3584,0,508,0,0,0,0,4,0,0,0,0,0,0]
    Req states 3: [3584,0,509,0,0,0,0,3,0,0,0,0,0,0]
    Req lat 1, us: 4169.757
    Req lat 2, us: 5629.531
    Req lat 3, us: 4136.811
  Device: "mlx5_1"
    Polls, comps, reqs: 2967952, 1581914, 790957
    Comps/poll: .532
    Req lat, us: 3749.652
    Req lat (total), us: 4127.519
    Req states 1: [3583,0,508,0,0,0,0,4,0,0,0,1,0,0]
    Req states 2: [3583,0,509,0,0,0,0,2,0,0,0,2,0,0]
    Req states 3: [3583,0,509,0,0,0,0,3,0,0,0,1,0,0]
    Req lat 1, us: 4129.940
    Req lat 2, us: 5530.674
    Req lat 3, us: 3853.771
Poll group: "nvmf_tgt_poll_group_7"
  Pacer calls, polls, ios: 2884457, 1688553, 1653954
  Pacer poll, io period, us: 24.824 25.343
  Pacer period 1, us: 22.796
  Pacer period 2, us: 22.796
  Pacer period 3, us: 22.796
  Device: "mlx5_0"
    Polls, comps, reqs: 2884457, 1726190, 863115
    Comps/poll: .598
    Req lat, us: 2125.312
    Req lat (total), us: 2818.057
    Req states 1: [3817,0,276,0,0,0,0,1,0,0,0,2,0,0]
    Req states 2: [3728,0,364,0,0,0,0,4,0,0,0,0,0,0]
    Req states 3: [3777,0,316,0,0,0,0,3,0,0,0,0,0,0]
    Req lat 1, us: 4743.063
    Req lat 2, us: 3971.255
    Req lat 3, us: 2924.934
  Device: "mlx5_1"
    Polls, comps, reqs: 2884457, 1581793, 790914
    Comps/poll: .548
    Req lat, us: 2587.222
    Req lat (total), us: 2906.083
    Req states 1: [3825,0,267,0,0,0,0,4,0,0,0,0,0,0]
    Req states 2: [3737,0,355,0,0,0,0,1,0,0,0,3,0,0]
    Req states 3: [3790,0,302,0,0,0,0,2,0,0,0,2,0,0]
    Req lat 1, us: 3580.901
    Req lat 2, us: 4094.080
    Req lat 3, us: 2859.373

~~~

**IO pacer log**

~~~
io_pacer.c: 213:spdk_io_pacer_create: *NOTICE*: Created IO pacer 0xaaaae1ee2490: period_ns 22800, period_ticks 3562, max_queues 0
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 23796 ns, new period 3718 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 33780 ns, new period 5278 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 43764 ns, new period 6838 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 260:spdk_io_pacer_create_queue: *NOTICE*: Allocated more queues for IO pacer 0xaaaae1ee2490: max_queues 32
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 0000000100000009
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 000000010000000d
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 0000000100000005
io_pacer.c: 267:spdk_io_pacer_create_queue: *NOTICE*: Created IO pacer queue: pacer 0xaaaae1ee2490, key 0000000100000001
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2287, io period 43725 ns, new period 42676 ns, new period 6668 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2433, io period 41101 ns, new period 40101 ns, new period 6265 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3171, io period 31535 ns, new period 30535 ns, new period 4771 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4286, io period 23331 ns, new period 22331 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4347, io period 23004 ns, new period 22004 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4353, io period 22972 ns, new period 21972 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4357, io period 22951 ns, new period 21951 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4358, io period 22946 ns, new period 21946 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4352, io period 22977 ns, new period 21977 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4360, io period 22935 ns, new period 21935 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3576, io period 27964 ns, new period 26964 ns, new period 4213 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3565, io period 28050 ns, new period 27050 ns, new period 4226 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3135, io period 31897 ns, new period 28155 ns, new period 4399 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4278, io period 23375 ns, new period 22375 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4333, io period 23078 ns, new period 22078 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4334, io period 23073 ns, new period 22073 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4356, io period 22956 ns, new period 21956 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2189, io period 45682 ns, new period 26792 ns, new period 4186 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2175, io period 45977 ns, new period 36776 ns, new period 5746 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2179, io period 45892 ns, new period 44892 ns, new period 7014 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2390, io period 41841 ns, new period 40841 ns, new period 6381 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3101, io period 32247 ns, new period 31247 ns, new period 4882 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4279, io period 23369 ns, new period 22369 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2840, io period 35211 ns, new period 26792 ns, new period 4186 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2927, io period 34164 ns, new period 33164 ns, new period 5181 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2975, io period 33613 ns, new period 28699 ns, new period 4484 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2693, io period 37133 ns, new period 36133 ns, new period 5645 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2542, io period 39339 ns, new period 38339 ns, new period 5990 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 3326, io period 30066 ns, new period 29066 ns, new period 4541 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4328, io period 23105 ns, new period 22105 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4332, io period 23084 ns, new period 22084 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4347, io period 23004 ns, new period 22004 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4339, io period 23046 ns, new period 22046 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4341, io period 23036 ns, new period 22036 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4345, io period 23014 ns, new period 22014 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4321, io period 23142 ns, new period 22142 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4342, io period 23030 ns, new period 22030 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4348, io period 22999 ns, new period 21999 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4352, io period 22977 ns, new period 21977 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4344, io period 23020 ns, new period 22020 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4339, io period 23046 ns, new period 22046 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4348, io period 22999 ns, new period 21999 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4353, io period 22972 ns, new period 21972 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4358, io period 22946 ns, new period 21946 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4335, io period 23068 ns, new period 22068 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4325, io period 23121 ns, new period 22121 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4357, io period 22951 ns, new period 21951 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4328, io period 23105 ns, new period 22105 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4335, io period 23068 ns, new period 22068 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4354, io period 22967 ns, new period 21967 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4357, io period 22951 ns, new period 21951 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4318, io period 23158 ns, new period 22158 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4347, io period 23004 ns, new period 22004 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4335, io period 23068 ns, new period 22068 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4353, io period 22972 ns, new period 21972 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4334, io period 23073 ns, new period 22073 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 4355, io period 22962 ns, new period 21962 ns, new period 3562 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 2204, io period 45372 ns, new period 28788 ns, new period 4498 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 38772 ns, new period 6058 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 168:io_pacer_tune: *NOTICE*: IO pacer tuner: pacer 0xaaaae1ee2490, ios 0, io period 100000000 ns, new period 46593 ns, new period 7124 ticks, min 3562, max 7124
io_pacer.c: 237:spdk_io_pacer_destroy: *NOTICE*: Destroyed IO pacer 0xaaaae1ee2490
~~~

### Test 15

Basic test with rate based IO pacing. Tuner disabled (fixed rate).

**IO pacing**: `Rate based`

**Configuration**: `config_nvme`

**Initiator**: `fio+SPDK`

**CPU mask**: 0xF0 (4 cores)

| Pacer period, us | QD   | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|------------------|------|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 5.6 (22.4)       | 256  | 160.0 | 180.231  | 3357.1      | 6.7       | 74.0        | 367.0 (45.8)         | 22.5             |
| 5.65 (22.6)      | 256  | 178.1 | 195.7152 | 3013.5      | 4.3       | 99.5        | 129.6 (16.2)         | 22.7             |
| 5.675 (22.7)     | 256  | 183.5 | 195.0755 | 2924.5      | .1        | 99.5        | 25.0 (3.1)           | 22.7             |
| 5.7 (22.8)       | 256  | 182.8 | 194.2888 | 2936.3      | .2        | 99.5        | 23.6 (2.9)           | 22.8             |
| 5.725 (22.9)     | 256  | 181.9 | 193.3365 | 2949.9      | .2        | 99.5        | 24.3 (3.0)           | 22.9             |
| 5.75 (23)        | 256  | 181.2 | 192.5431 | 2961.5      | .2        | 99.5        | 22.6 (2.8)           | 23.0             |
| 5.8 (23.2)       | 256  | 179.7 | 190.9718 | 2986.4      | .3        | 99.5        | 22.6 (2.8)           | 23.2             |
| 6 (24)           | 256  | 169.8 | 184.7295 | 3163.1      | 1.0       | 99.5        | 183.6 (22.9)         | 24.0             |
| 5.6 (22.4)       | 1024 | 156.1 | 170.3481 | 11276.8     | 5.7       | 76.7        | 596.0 (74.5)         | 22.5             |
| 5.65 (22.6)      | 1024 | 154.2 | 171.9468 | 11708.2     | 5.4       | 73.9        | 588.6 (73.5)         | 22.7             |
| 5.675 (22.7)     | 1024 | 141.7 | 165.9734 | 10886.6     | 9.2       | 58.9        | 572.6 (71.5)         | 22.8             |
| 5.7 (22.8)       | 1024 | 160.9 | 148.8915 | 12118.0     | 11.1      | 67.7        | 255.6 (31.9)         | 22.8             |
| 5.725 (22.9)     | 1024 | 137.9 | 124.2786 | 11597.4     | 10.7      | 60.5        | 758.0 (94.7)         | 23.0             |
| 5.75 (23)        | 1024 | 152.6 | 192.9411 | 11941.0     | 13.8      | 99.2        | 428.0 (53.5)         | 23.0             |
| 5.8 (23.2)       | 1024 | 157.3 | 134.1641 | 12723.2     | 11.6      | 65.3        | 28.3 (3.5)           | 23.2             |
| 6 (24)           | 1024 | 173.7 | 184.5522 | 12364.5     | .5        | 99.5        | 22.3 (2.7)           | 24.0             |

### Test 16

IO pacer period 5750, adjusted period 23000, num delay 16

| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 169.6 | 191.0841 | 12737.7     | 3.4       | 99.4        | 19.0 (2.3)           | 26.7             |
| 2  | 175.5 | 190.674  | 12290.3     | 1.3       | 99.4        | 21.0 (2.6)           | 26.2             |
| 4  | 175.1 | 190.9027 | 12369.1     | 2.5       | 99.3        | 22.0 (2.7)           | 26.1             |
| 8  | 179.4 | 190.7852 | 12162.6     | .9        | 98.9        | 30.6 (3.8)           | 25.9             |
| 16 | 179.2 | 190.2876 | 12363.9     | 1.0       | 97.3        | 38.6 (4.8)           | 25.8             |
| 32 | 123.5 | 114.2105 | 18478.2     | 4.9       | 38.4        | 1293.3 (161.6)       | 27.0             |
| 64 | 123.1 | 110.4748 | 19634.4     | 5.1       | 30.6        | 1319.3 (164.9)       | 28.1             |

IO pacer period 5750, adjusted period 23000, num delay 32

| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 175.9 | 191.2743 | 12239.3     | 3.1       | 99.4        | 16.0 (2.0)           | 25.5             |
| 2  | 179.6 | 190.8678 | 12006.9     | .2        | 99.4        | 23.0 (2.8)           | 25.4             |
| 4  | 173.5 | 190.4886 | 12486.1     | .2        | 99.1        | 29.0 (3.6)           | 25.6             |
| 8  | 178.6 | 189.9393 | 12211.3     | .3        | 97.8        | 41.0 (5.1)           | 25.5             |
| 16 | 105.0 | 110.8799 | 21078.7     | 2.2       | 44.3        | 1336.3 (167.0)       | 27.6             |
| 32 | 104.6 | 110.4205 | 21820.5     | 1.9       | 34.1        | 1379.6 (172.4)       | 29.2             |
| 64 | 104.5 | 110.3843 | 23120.3     | 1.5       | 30.0        | 1079.0 (134.8)       | 30.4             |

IO pacer period 6000, adjusted period 24000, num delay 16

| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 163.5 | 183.6816 | 13211.4     | 4.2       | 92.7        | 17.0 (2.1)           | 27.2             |
| 2  | 172.3 | 183.4786 | 12484.2     | .8        | 99.4        | 19.6 (2.4)           | 26.8             |
| 4  | 172.6 | 183.2886 | 12542.7     | .6        | 99.4        | 20.3 (2.5)           | 26.7             |
| 8  | 172.5 | 183.1826 | 12648.9     | 1.1       | 99.1        | 25.3 (3.1)           | 26.6             |
| 16 | 172.3 | 183.0874 | 12856.7     | 1.0       | 97.3        | 38.6 (4.8)           | 26.6             |
| 32 | 154.1 | 182.1496 | 14811.4     | 4.7       | 90.7        | 714.0 (89.2)         | 27.2             |
| 64 | 171.2 | 182.0205 | 14119.8     | .5        | 88.1        | 52.0 (6.5)           | 27.1             |

IO pacer period 6000, adjusted period 24000, num delay 32

| QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 1  | 172.5 | 183.4912 | 12471.7     | .3        | 99.4        | 16.3 (2.0)           | 26.1             |
| 2  | 172.4 | 183.0833 | 12503.9     | .3        | 99.3        | 24.0 (3.0)           | 26.3             |
| 4  | 166.5 | 98.1667  | 13021.3     | 3.4       | 99.1        | 28.6 (3.5)           | 26.5             |
| 8  | 171.8 | 182.5819 | 12699.0     | .4        | 96.4        | 37.0 (4.6)           | 26.5             |
| 16 | 137.2 | 181.5809 | 16143.7     | 7.6       | 89.5        | 588.6 (73.5)         | 27.7             |
| 32 | 105.5 | 111.3706 | 19815.1     | 2.0       | 35.0        | 897.6 (112.2)        | 29.3             |
| 64 | 104.3 | 110.2806 | 23161.0     | 1.5       | 29.6        | 1436.6 (179.5)       | 30.5             |

### Test 17

Test 12 with pacer and per disk credits. QD to job 3 is 1024 per
initiator. QD to jobs 1 and 2 is in the table. Total QD is `1024*2 + QD*2*2`.

CPU mask 0xF0, num cores 4, IO pacer period 5750, adjusted period 23000

| Num delay | Disk credit | QD | BW    | BW Max | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|-----------|-------------|----|-------|--------|----------|-------------|-----------|-------------|----------------------|------------------|
| 0         | 0           | 1  | 139.8 | 169.1  | 147.2441 | 15396.3     | 1.1       | 99.4        | 17.6 (2.2)           | 23.2             |
| 0         | 0           | 2  | 159.8 | 191.1  | 177.3752 | 13493.3     | 5.2       | 99.4        | 16.6 (2.0)           | 23.5             |
| 0         | 0           | 4  | 172.5 | 198.7  | 183.311  | 12550.8     | 1.2       | 99.4        | 17.3 (2.1)           | 23.4             |
| 0         | 0           | 8  | 178.8 | 211.0  | 190.127  | 12206.3     | 1.4       | 99.4        | 20.6 (2.5)           | 23.3             |
| 0         | 0           | 16 | 179.6 | 210.4  | 191.2127 | 12333.6     | 1.3       | 99.4        | 19.0 (2.3)           | 23.3             |
| 0         | 0           | 32 | 144.9 | 204.9  | 191.026  | 15758.2     | 7.3       | 99.3        | 77.6 (9.7)           | 23.9             |
| 0         | 0           | 64 | 148.2 | 181.6  | 191.4018 | 16302.2     | 6.3       | 92.8        | 95.0 (11.8)          | 24.1             |
| 16        | 0           | 1  | 162.0 | 188.5  | 191.1772 | 13285.0     | 8.6       | 99.4        | 192.6 (24.0)         | 24.7             |
| 16        | 0           | 2  | 177.6 | 194.5  | 190.95   | 12277.0     | 4.1       | 98.8        | 19.6 (2.4)           | 24.1             |
| 16        | 0           | 4  | 131.1 | 190.7  | 119.2169 | 16582.4     | 7.6       | 96.3        | 28.0 (3.5)           | 24.1             |
| 16        | 0           | 8  | 168.7 | 199.5  | 179.6315 | 12935.4     | 1.5       | 98.8        | 26.3 (3.2)           | 23.9             |
| 16        | 0           | 16 | 172.5 | 202.4  | 183.0719 | 12847.2     | 1.2       | 97.1        | 36.3 (4.5)           | 23.8             |
| 16        | 0           | 32 | 126.6 | 211.7  | 106.2463 | 17627.2     | 6.8       | 61.8        | 61.6 (7.7)           | 24.3             |
| 16        | 0           | 64 | 146.3 | 175.2  | 183.0758 | 16525.2     | 5.5       | 87.7        | 130.3 (16.2)         | 24.5             |
| 32        | 0           | 1  | 162.1 | 174.0  | 171.8491 | 13274.6     | .5        | 99.4        | 19.6 (2.4)           | 23.2             |
| 32        | 0           | 2  | 136.2 | 173.6  | 118.3583 | 15833.4     | 7.0       | 95.7        | 23.3 (2.9)           | 23.7             |
| 32        | 0           | 4  | 116.8 | 145.3  | 112.065  | 18519.8     | 3.2       | 97.3        | 46.3 (5.7)           | 23.6             |
| 32        | 0           | 8  | 124.8 | 162.6  | 142.9066 | 17361.5     | 6.1       | 97.8        | 42.3 (5.2)           | 23.7             |
| 32        | 0           | 16 | 167.0 | 184.8  | 177.7424 | 13261.3     | .7        | 89.7        | 55.3 (6.9)           | 23.7             |
| 32        | 0           | 32 | 114.7 | 171.9  | 127.4941 | 19914.7     | 2.5       | 73.1        | 52.3 (6.5)           | 24.4             |
| 32        | 0           | 64 | 107.1 | 163.0  | 122.2749 | 22505.9     | 2.1       | 68.8        | 80.6 (10.0)          | 25.1             |
| 0         | 2           | 1  | 123.2 | 178.5  | 15.5349  | 13499.1     | 4.2       | 99.4        | 16.3 (2.0)           | 23.1             |
| 0         | 2           | 2  | 174.0 | 206.9  | 191.3371 | 12372.3     | 4.0       | 99.4        | 15.3 (1.9)           | 23.1             |
| 0         | 2           | 4  | 173.2 | 234.7  | 191.2245 | 12066.4     | 4.0       | 99.4        | 16.0 (2.0)           | 23.1             |
| 0         | 2           | 8  | 179.5 | 222.7  | 191.0261 | 12158.1     | 1.9       | 99.4        | 16.3 (2.0)           | 23.1             |
| 0         | 2           | 16 | 179.5 | 207.5  | 191.1639 | 12342.1     | 1.3       | 99.4        | 17.0 (2.1)           | 23.1             |
| 0         | 2           | 32 | 179.4 | 194.4  | 191.0426 | 12729.8     | .5        | 99.4        | 15.6 (1.9)           | 23.1             |
| 0         | 2           | 64 | 168.2 | 194.6  | 190.0671 | 11845.9     | 2.4       | 99.2        | 25.3 (3.1)           | 23.1             |
| 16        | 2           | 1  | 162.9 | 178.4  | 173.0717 | 13209.8     | .6        | 99.4        | 18.3 (2.2)           | 23.1             |
| 16        | 2           | 2  | 169.3 | 202.6  | 189.0357 | 11988.5     | 1.7       | 99.3        | 19.3 (2.4)           | 23.1             |
| 16        | 2           | 4  | 164.8 | 188.9  | 175.5552 | 13137.7     | 1.1       | 99.4        | 20.0 (2.5)           | 23.1             |
| 16        | 2           | 8  | 167.6 | 234.5  | 190.4124 | 12650.1     | 4.1       | 99.3        | 24.6 (3.0)           | 23.1             |
| 16        | 2           | 16 | 178.4 | 209.1  | 190.1054 | 12417.8     | 1.4       | 98.1        | 34.0 (4.2)           | 23.1             |
| 16        | 2           | 32 | 178.0 | 193.6  | 189.6761 | 12826.6     | .5        | 95.4        | 43.6 (5.4)           | 23.1             |
| 16        | 2           | 64 | 174.1 | 194.9  | 185.3437 | 13884.6     | .5        | 95.8        | 42.3 (5.2)           | 23.2             |
| 32        | 2           | 1  | 146.7 | 173.0  | 170.6181 | 14673.9     | 4.0       | 99.4        | 14.0 (1.7)           | 23.1             |
| 32        | 2           | 2  | 167.0 | 183.1  | 188.0173 | 12616.6     | 3.3       | 99.4        | 21.6 (2.7)           | 23.1             |
| 32        | 2           | 4  | 176.5 | 183.8  | 188.0139 | 12170.8     | .4        | 99.2        | 28.0 (3.5)           | 23.1             |
| 32        | 2           | 8  | 152.1 | 181.1  | 173.6008 | 14149.3     | 4.0       | 97.9        | 41.0 (5.1)           | 23.1             |
| 32        | 2           | 16 | 174.1 | 189.8  | 185.3632 | 10819.0     | .6        | 87.6        | 61.0 (7.6)           | 23.2             |
| 32        | 2           | 32 | 158.7 | 181.3  | 170.3972 | 14185.5     | .7        | 77.7        | 80.6 (10.0)          | 23.5             |
| 32        | 2           | 64 | 158.6 | 184.7  | 169.1071 | 15123.3     | .7        | 77.5        | 73.6 (9.2)           | 23.8             |
| 0         | 6           | 1  | 179.5 | 191.0  | 191.2481 | 11976.5     | .9        | 99.4        | 16.0 (2.0)           | 23.2             |
| 0         | 6           | 2  | 179.5 | 190.1  | 191.0778 | 12009.1     | .5        | 99.4        | 15.0 (1.8)           | 23.2             |
| 0         | 6           | 4  | 168.1 | 229.4  | 183.2442 | 12879.5     | 3.6       | 99.4        | 19.0 (2.3)           | 23.2             |
| 0         | 6           | 8  | 179.5 | 214.2  | 190.9545 | 12158.6     | 1.5       | 99.4        | 17.3 (2.1)           | 23.2             |
| 0         | 6           | 16 | 179.6 | 204.6  | 191.1447 | 12339.6     | .9        | 99.4        | 17.0 (2.1)           | 23.2             |
| 0         | 6           | 32 | 179.5 | 194.2  | 190.9506 | 12720.9     | .5        | 99.4        | 14.6 (1.8)           | 23.2             |
| 0         | 6           | 64 | 179.1 | 199.5  | 191.0367 | 13494.5     | .5        | 99.4        | 19.0 (2.3)           | 23.2             |
| 16        | 6           | 1  | 168.9 | 187.7  | 191.2896 | 12743.7     | 4.9       | 99.5        | 23.6 (2.9)           | 23.2             |
| 16        | 6           | 2  | 179.3 | 186.5  | 190.8962 | 12023.5     | .4        | 99.4        | 18.0 (2.2)           | 23.2             |
| 16        | 6           | 4  | 179.2 | 190.4  | 190.5693 | 12082.4     | .5        | 99.3        | 22.3 (2.7)           | 23.2             |
| 16        | 6           | 8  | 169.3 | 197.8  | 180.0563 | 12887.5     | 1.2       | 99.3        | 24.0 (3.0)           | 23.2             |
| 16        | 6           | 16 | 178.7 | 200.7  | 190.1363 | 12402.9     | 1.0       | 98.3        | 37.3 (4.6)           | 23.2             |
| 16        | 6           | 32 | 173.6 | 197.1  | 185.4268 | 13151.6     | .8        | 89.1        | 57.0 (7.1)           | 23.3             |
| 16        | 6           | 64 | 172.6 | 195.3  | 182.7844 | 14006.3     | .7        | 86.9        | 58.0 (7.2)           | 23.4             |
| 32        | 6           | 1  | 169.3 | 181.6  | 190.7255 | 13114.2     | 2.7       | 99.4        | 18.0 (2.2)           | 23.2             |
| 32        | 6           | 2  | 135.8 | 175.2  | 170.2233 | 12721.0     | 5.7       | 99.2        | 36.0 (4.5)           | 23.2             |
| 32        | 6           | 4  | 147.2 | 185.1  | 190.9792 | 13685.5     | 6.0       | 99.2        | 28.3 (3.5)           | 23.2             |
| 32        | 6           | 8  | 141.2 | 166.6  | 149.3501 | 8225.9      | .9        | 98.0        | 40.0 (5.0)           | 23.2             |
| 32        | 6           | 16 | 176.7 | 188.2  | 187.2539 | 12535.7     | .5        | 88.9        | 56.3 (7.0)           | 23.3             |
| 32        | 6           | 32 | 116.1 | 165.8  | 114.957  | 19668.2     | 1.9       | 65.9        | 56.3 (7.0)           | 24.0             |
| 32        | 6           | 64 | 116.2 | 166.3  | 122.1312 | 20818.5     | 1.5       | 69.2        | 70.0 (8.7)           | 24.5             |

#### Adaptive per disk credits

Results are not stable with Intel setup. So, each test was run 5
times. All runs are in the tables below. Fio runs 3 jobs per
initiator, 16 disks per job. QD in the table is applied to all
jobs. Total queue depth is `QD*num_jobs*num_hosts = QD*3*2`.

**Fast disks credits are limited (always in cache)**

CPU mask 0xF0, num cores 4, IO pacer period 5750, adjusted period 23000, disk credit 10

| Num delay | QD/jobs | Total QD | BW    | BW Max | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|-----------|---------|----------|-------|--------|----------|-------------|-----------|-------------|----------------------|------------------|
| 0         | 85      | 510      | 172.3 | 337.6  | 191.2859 | 3140.4      | 7.9       | 99.4        | 16.0 (2.0)           | 23.1             |
| 0         | 85      | 510      | 179.7 | 183.5  | 190.6689 | 2975.7      | .1        | 99.4        | 18.0 (2.2)           | 23.1             |
| 0         | 85      | 510      |       |        | 99.4     | 23.1        | 16.3      |             |                      |                  |
| 0         | 85      | 510      | 179.4 | 184.9  | 190.9048 | 2979.0      | .1        | 99.4        | 20.3 (2.5)           | 23.1             |
| 0         | 85      | 510      | 121.9 | 330.9  | 158.2636 | 4566.2      | 11.9      | 99.4        | 16.6 (2.0)           | 23.1             |
| 0         | 341     | 2046     | 155.7 | 431.3  | 191.0951 | 14260.7     | 10.9      | 99.4        | 24.0 (3.0)           | 23.1             |
| 0         | 341     | 2046     | 160.6 | 388.8  | 0        | 13362.8     | 10.5      | 99.3        | 18.3 (2.2)           | 23.1             |
| 0         | 341     | 2046     | 116.9 | 318.5  | 154.3323 | 18042.2     | 11.1      | 99.3        | 28.0 (3.5)           | 23.1             |
| 0         | 341     | 2046     | 132.2 | 320.3  | 36.0768  | 16221.6     | 11.5      | 99.4        | 22.6 (2.8)           | 23.1             |
| 0         | 341     | 2046     | 152.2 | 351.8  | 191.0389 | 14317.2     | 11.0      | 99.4        | 15.6 (1.9)           | 23.1             |
| 16        | 85      | 510      | 179.1 | 196.4  | 190.2086 | 2983.3      | 1.3       | 99.3        | 21.3 (2.6)           | 23.2             |
| 16        | 85      | 510      | 174.6 | 196.6  | 190.5897 | 3012.1      | 1.1       | 99.4        | 25.3 (3.1)           | 23.2             |
| 16        | 85      | 510      | 166.8 | 197.4  | 190.4565 | 3196.1      | 3.2       | 99.2        | 25.3 (3.1)           | 23.2             |
| 16        | 85      | 510      | 178.4 | 185.5  | 190.3233 | 2992.7      | .2        | 99.2        | 25.3 (3.1)           | 23.2             |
| 16        | 85      | 510      | 178.7 | 192.6  | 191.2005 | 3024.0      | 1.2       | 99.2        | 24.6 (3.0)           | 23.1             |
| 16        | 341     | 2046     | 165.4 | 272.4  | 190.5597 | 12834.9     | 5.8       | 99.2        | 26.0 (3.2)           | 23.1             |
| 16        | 341     | 2046     | 153.9 | 262.9  | 181.5323 | 13835.0     | 7.2       | 99.3        | 31.3 (3.9)           | 23.1             |
| 16        | 341     | 2046     | 171.9 | 193.0  | 190.7071 | 12402.4     | 2.7       | 99.2        | 21.6 (2.7)           | 23.1             |
| 16        | 341     | 2046     | 147.1 | 187.1  | 181.9225 | 14644.3     | 3.1       | 99.3        | 23.6 (2.9)           | 23.1             |
| 16        | 341     | 2046     | 171.5 | 343.3  | 184.3254 | 12581.8     | 7.8       | 99.4        | 32.0 (4.0)           | 23.1             |
| 32        | 85      | 510      | 161.5 | 192.1  | 171.646  | 3269.2      | 2.1       | 99.3        | 33.3 (4.1)           | 23.2             |
| 32        | 85      | 510      | 178.6 | 205.4  | 190.2686 | 3049.7      | 1.7       | 98.1        | 36.0 (4.5)           | 23.2             |
| 32        | 85      | 510      | 173.1 | 196.4  | 190.7188 | 3026.7      | 2.0       | 98.5        | 28.0 (3.5)           | 23.2             |
| 32        | 85      | 510      | 178.2 | 196.8  | 189.2059 | 2997.1      | 1.8       | 98.7        | 30.6 (3.8)           | 23.2             |
| 32        | 85      | 510      | 162.3 | 193.5  | 171.7698 | 3378.7      | 1.9       | 98.5        | 30.0 (3.7)           | 23.2             |
| 32        | 341     | 2046     | 160.9 | 210.5  | 189.5707 | 13291.8     | 4.9       | 98.1        | 33.6 (4.2)           | 23.2             |
| 32        | 341     | 2046     | 153.0 | 189.4  | 173.7415 | 14567.9     | 3.5       | 99.4        | 27.3 (3.4)           | 23.1             |
| 32        | 341     | 2046     | 152.8 | 190.6  | 175.7529 | 13992.5     | 5.1       | 98.5        | 32.6 (4.0)           | 23.1             |
| 32        | 341     | 2046     | 159.7 | 198.0  | 172.9828 | 13359.9     | 2.3       | 98.7        | 37.0 (4.6)           | 23.1             |
| 32        | 341     | 2046     | 153.3 | 192.7  | 171.7546 | 13848.7     | 3.3       | 98.6        | 39.3 (4.9)           | 23.1             |

**Fast disks credits are unlimited**

CPU mask 0xF0, num cores 4, IO pacer period 5750, adjusted period 23000

| Num delay | QD/job | Total QD | BW    | BW Max | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|-----------|--------|----------|-------|--------|----------|-------------|-----------|-------------|----------------------|------------------|
| 0         | 85     | 510      | 169.4 | 243.9  | 190.925  | 3156.2      | 4.7       | 99.4        | 15.0 (1.8)           | 23.5             |
| 0         | 85     | 510      | 170.9 | 188.8  | 190.9532 | 3128.4      | 4.6       | 99.4        | 16.6 (2.0)           | 23.4             |
| 0         | 85     | 510      | 176.7 | 365.1  | 190.7155 | 3093.1      | 8.2       | 99.4        | 17.6 (2.2)           | 23.3             |
| 0         | 85     | 510      | 179.1 | 183.0  | 191.2348 | 2984.1      | .2        | 99.4        | 13.6 (1.7)           | 23.3             |
| 0         | 85     | 510      | 145.6 | 359.5  | 191.2212 | 3792.3      | 11.3      | 99.4        | 12.0 (1.5)           | 23.3             |
| 0         | 341    | 2046     | 135.9 | 185.0  | 190.2918 | 15635.7     | 9.0       | 99.3        | 15.0 (1.8)           | 23.8             |
| 0         | 341    | 2046     | 133.4 | 185.1  | 187.8563 | 15950.1     | 7.9       | 99.3        | 56.3 (7.0)           | 24.1             |
| 0         | 341    | 2046     | 132.1 | 320.2  | 174.476  | 16060.4     | 10.9      | 98.7        | 16.0 (2.0)           | 24.1             |
| 0         | 341    | 2046     | 122.7 | 316.7  | 0        | 17640.1     | 11.5      | 99.4        | 23.0 (2.8)           | 24.0             |
| 0         | 341    | 2046     | 161.8 | 186.2  | 190.7745 | 13263.1     | 5.2       | 99.3        | 17.0 (2.1)           | 24.0             |
| 16        | 85     | 510      | 178.4 | 195.1  | 190.225  | 2993.3      | 1.3       | 99.3        | 25.6 (3.2)           | 23.3             |
| 16        | 85     | 510      | 178.2 | 194.9  | 190.0175 | 2997.1      | 1.1       | 99.0        | 25.3 (3.1)           | 23.2             |
| 16        | 85     | 510      | 172.5 | 186.8  | 182.4327 | 3094.6      | .9        | 99.1        | 29.3 (3.6)           | 23.2             |
| 16        | 85     | 510      | 178.4 | 195.1  | 190.8851 | 2991.2      | 1.1       | 98.9        | 24.0 (3.0)           | 23.2             |
| 16        | 85     | 510      | 172.6 | 186.8  | 184.1523 | 3101.4      | 1.0       | 99.0        | 23.3 (2.9)           | 23.2             |
| 16        | 341    | 2046     | 160.2 | 195.6  | 190.1466 | 13267.8     | 4.5       | 99.0        | 247.3 (30.9)         | 23.3             |
| 16        | 341    | 2046     | 150.0 | 196.7  | 188.9012 | 14219.5     | 6.1       | 98.8        | 25.3 (3.1)           | 23.6             |
| 16        | 341    | 2046     | 170.3 | 195.5  | 191.5911 | 12587.1     | 3.2       | 98.7        | 22.3 (2.7)           | 23.6             |
| 16        | 341    | 2046     | 156.5 | 187.1  | 183.5859 | 13707.8     | 5.0       | 99.3        | 32.6 (4.0)           | 23.7             |
| 16        | 341    | 2046     | 162.5 | 197.8  | 189.649  | 13078.6     | 6.5       | 99.2        | 18.6 (2.3)           | 23.7             |
| 32        | 85     | 510      | 174.4 | 200.5  | 189.9468 | 3021.0      | 1.6       | 98.3        | 28.6 (3.5)           | 23.2             |
| 32        | 85     | 510      | 177.7 | 206.3  | 189.6822 | 3002.2      | 1.8       | 97.8        | 31.6 (3.9)           | 23.2             |
| 32        | 85     | 510      | 178.4 | 216.2  | 189.9447 | 2995.4      | 2.3       | 98.9        | 27.0 (3.3)           | 23.2             |
| 32        | 85     | 510      | 166.1 | 198.3  | 189.6234 | 3138.7      | 3.7       | 97.6        | 31.6 (3.9)           | 23.3             |
| 32        | 85     | 510      | 162.5 | 193.3  | 173.7788 | 3287.0      | 1.6       | 98.6        | 29.0 (3.6)           | 23.3             |
| 32        | 341    | 2046     | 176.2 | 209.9  | 189.4845 | 12195.5     | 1.9       | 97.8        | 36.3 (4.5)           | 23.3             |
| 32        | 341    | 2046     | 171.4 | 205.9  | 189.4546 | 12510.8     | 3.6       | 97.8        | 33.3 (4.1)           | 23.3             |
| 32        | 341    | 2046     | 171.5 | 210.2  | 189.9752 | 12586.2     | 4.1       | 96.9        | 31.0 (3.8)           | 23.4             |
| 32        | 341    | 2046     | 168.1 | 208.2  | 189.1935 | 12725.2     | 5.8       | 97.4        | 28.0 (3.5)           | 23.4             |
| 32        | 341    | 2046     | 161.3 | 192.5  | 172.7702 | 13424.1     | 1.9       | 98.8        | 35.6 (4.4)           | 23.4             |

**Different number of total credits**

Because of unstable results each test was run 3 times and best of 3
was placed into the table. Zero total credits means that per disk
credits are disabled (unlimited).

CPU mask 0xF0, num cores 4, IO pacer period 5750, adjusted period 23000

| Total credits, MB | Num delay | QD/job | Total QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|-------------------|-----------|--------|----------|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 0                 | 0         | 85     | 510      | 179.8 | 191.3018 | 2972.7      | .1        | 99.5        | 16.0 (2.0)           | 23.2             |
| 0                 | 0         | 341    | 2046     | 174.3 | 191.082  | 12641.4     | 2.1       | 99.4        | 15.3 (1.9)           | 24.3             |
| 0                 | 16        | 85     | 510      | 176.1 | 187.0778 | 3036.1      | .2        | 86.9        | 61.3 (7.6)           | 23.6             |
| 0                 | 16        | 341    | 2046     | 175.4 | 186.0555 | 12226.6     | .2        | 86.8        | 54.3 (6.7)           | 23.7             |
| 0                 | 32        | 85     | 510      | 117.3 | 125.5267 | 4557.0      | 1.2       | 67.8        | 67.6 (8.4)           | 29.2             |
| 0                 | 32        | 341    | 2046     | 118.8 | 124.2585 | 18053.1     | 1.1       | 70.0        | 90.6 (11.3)          | 29.1             |
| 12                | 0         | 85     | 510      | 179.7 | 191.2297 | 2974.6      | .1        | 99.4        | 14.3 (1.7)           | 23.1             |
| 12                | 0         | 341    | 2046     | 168.6 | 191.3158 | 12720.2     | 3.5       | 99.3        | 16.3 (2.0)           | 23.1             |
| 12                | 16        | 85     | 510      | 178.7 | 189.6586 | 2988.7      | 1.2       | 99.4        | 25.0 (3.1)           | 23.1             |
| 12                | 16        | 341    | 2046     | 161.1 | 183.9784 | 13063.2     | 2.9       | 99.2        | 28.0 (3.5)           | 23.1             |
| 12                | 32        | 85     | 510      | 177.9 | 189.7365 | 3062.0      | 2.1       | 99.3        | 33.0 (4.1)           | 23.2             |
| 12                | 32        | 341    | 2046     | 163.0 | 81.9526  | 12944.3     | 5.0       | 98.6        | 34.0 (4.2)           | 23.2             |
| 15                | 0         | 85     | 510      | 179.7 | 190.9098 | 2974.3      | 3.5       | 99.5        | 14.3 (1.7)           | 23.1             |
| 15                | 0         | 341    | 2046     | 146.2 | 192.1273 | 14669.6     | 6.7       | 99.3        | 18.3 (2.2)           | 23.2             |
| 15                | 16        | 85     | 510      | 178.6 | 190.587  | 2988.6      | 1.0       | 99.3        | 28.3 (3.5)           | 23.2             |
| 15                | 16        | 341    | 2046     | 157.9 | 130.9454 | 13098.9     | 2.5       | 99.1        | 24.0 (3.0)           | 23.5             |
| 15                | 32        | 85     | 510      | 178.3 | 190.192  | 2997.2      | 2.2       | 99.4        | 33.6 (4.2)           | 23.2             |
| 15                | 32        | 341    | 2046     | 169.2 | 189.4506 | 12762.9     | 6.0       | 98.7        | 35.3 (4.4)           | 23.2             |
| 18                | 0         | 85     | 510      | 179.4 | 190.8951 | 2979.2      | .1        | 99.4        | 17.0 (2.1)           | 23.3             |
| 18                | 0         | 341    | 2046     | 164.3 | 190.8764 | 12948.6     | 3.8       | 99.4        | 20.0 (2.5)           | 23.2             |
| 18                | 16        | 85     | 510      | 178.7 | 189.6559 | 2988.5      | .8        | 99.0        | 22.6 (2.8)           | 23.3             |
| 18                | 16        | 341    | 2046     | 173.0 | 189.8246 | 12368.2     | 1.2       | 99.0        | 23.0 (2.8)           | 23.3             |
| 18                | 32        | 85     | 510      | 176.2 | 187.8994 | 3033.4      | .8        | 89.4        | 52.0 (6.5)           | 23.5             |
| 18                | 32        | 341    | 2046     | 167.1 | 93.8745  | 12828.2     | 2.2       | 88.4        | 55.0 (6.8)           | 23.4             |
| 24                | 0         | 85     | 510      | 179.6 | 191.22   | 2977.1      | .1        | 99.5        | 17.0 (2.1)           | 23.3             |
| 24                | 0         | 341    | 2046     | 168.6 | 190.5414 | 12723.7     | 2.2       | 99.3        | 45.6 (5.7)           | 23.3             |
| 24                | 16        | 85     | 510      | 178.2 | 189.7588 | 2997.5      | .2        | 97.5        | 35.6 (4.4)           | 23.4             |
| 24                | 16        | 341    | 2046     | 169.5 | 185.9885 | 12535.1     | 1.0       | 97.9        | 46.0 (5.7)           | 23.3             |
| 24                | 32        | 85     | 510      | 176.1 | 187.9351 | 3034.4      | .8        | 89.0        | 50.0 (6.2)           | 23.5             |
| 24                | 32        | 341    | 2046     | 167.9 | 185.4839 | 12749.4     | 3.5       | 89.7        | 54.0 (6.7)           | 23.5             |
| 120               | 0         | 85     | 510      | 179.4 | 190.5426 | 2979.4      | .1        | 99.4        | 15.0 (1.8)           | 23.2             |
| 120               | 0         | 341    | 2046     | 178.4 | 190.2509 | 12017.3     | .2        | 98.3        | 21.0 (2.6)           | 23.9             |
| 120               | 16        | 85     | 510      | 176.2 | 187.7906 | 3034.1      | .3        | 87.4        | 54.3 (6.7)           | 23.6             |
| 120               | 16        | 341    | 2046     | 175.2 | 185.2566 | 12243.7     | .4        | 86.9        | 68.0 (8.5)           | 23.7             |
| 120               | 32        | 85     | 510      | 115.9 | 126.3896 | 4612.7      | 1.3       | 69.1        | 83.3 (10.4)          | 28.8             |
| 120               | 32        | 341    | 2046     | 116.3 | 124.92   | 18448.9     | 1.4       | 64.2        | 67.3 (8.4)           | 28.9             |

### Test 18

Mixed IO sizes.

Total queue depth (max number of in-flight IO requests) is `QD*num_jobs*num_hosts = QD*8*2`

#### IO rate based tuner

CPU mask 0xFFFF, IO pacer period 1425, adjusted period 22800, credit size 32768, num buffers 131072, buf cache 8192

| IO size        | Pacer threshold | QD/job | Total QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----------------|-----------------|--------|----------|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 128k           | 0               | 32     | 512      | 179.3 | 193.8197 | 2992.4      | .7        | 99.4        | 373.3 (2.9)          | 24.4             |
| 128k/80:4k/20  | 0               | 32     | 512      | 178.8 | 193.4911 | 2420.2      | .7        | 99.2        | 414.6 (3.2)          | 24.5             |
| 128k/20:4k/80  | 0               | 32     | 512      | 168.1 | 182.5027 | 717.8       | .9        | 98.4        | 242.6 (1.8)          | 25.3             |
| 128k/80:8k/20  | 0               | 32     | 512      | 177.6 | 193.1206 | 2455.2      | .8        | 99.2        | 145.3 (1.1)          | 29.0             |
| 128k/20:8k/80  | 0               | 32     | 512      | 169.3 | 186.1091 | 792.1       | 1.0       | 98.6        | 128.6 (1.0)          | 28.8             |
| 128k/80:16k/20 | 0               | 32     | 512      | 179.4 | 193.7575 | 2468.0      | .7        | 99.2        | 412.0 (3.2)          | 24.4             |
| 128k/20:16k/80 | 0               | 32     | 512      | 174.9 | 189.4814 | 920.2       | .9        | 98.8        | 296.6 (2.3)          | 24.8             |
| 128k           | 4096            | 32     | 512      | 180.0 | 191.7095 | 2981.0      | .6        | 99.4        | 368.0 (2.8)          | 24.4             |
| 128k/80:4k/20  | 4096            | 32     | 512      | 173.4 | 194.4179 | 2495.4      | 1.0       | 98.6        | 441.3 (3.4)          | 25.2             |
| 128k/20:4k/80  | 4096            | 32     | 512      | 156.3 | 162.1683 | 771.9       | .9        | 87.7        | 533.6 (4.1)          | 28.5             |
| 128k/80:16k/20 | 4096            | 32     | 512      | 179.3 | 193.5959 | 2469.4      | .7        | 99.2        | 370.0 (2.8)          | 24.5             |
| 128k/20:16k/80 | 4096            | 32     | 512      | 175.8 | 187.4908 | 919.7       | 1.0       | 98.8        | 266.6 (2.0)          | 24.9             |
| 128k/80:8k/20  | 8192            | 32     | 512      | 157.7 | 157.4266 | 2764.4      | 1.4       | 94.1        | 160.6 (1.2)          | 30.5             |
| 128k/20:8k/80  | 8192            | 32     | 512      | 158.2 | 165.2571 | 847.1       | .9        | 87.4        | 207.3 (1.6)          | 33.8             |
| 128k           | 16384           | 32     | 512      | 179.7 | 193.9777 | 2986.2      | .7        | 99.4        | 384.0 (3.0)          | 24.4             |
| 128k/80:4k/20  | 16384           | 32     | 512      | 174.2 | 193.1418 | 2484.2      | 1.0       | 97.1        | 467.6 (3.6)          | 25.1             |
| 128k/20:4k/80  | 16384           | 32     | 512      | 155.8 | 159.8623 | 774.4       | .8        | 88.4        | 430.6 (3.3)          | 28.5             |
| 128k/80:16k/20 | 16384           | 32     | 512      | 140.1 | 144.2609 | 3159.6      | 1.1       | 84.3        | 3160.6 (24.6)        | 29.7             |
| 128k/20:16k/80 | 16384           | 32     | 512      | 145.7 | 150.9739 | 1104.6      | .7        | 84.2        | 1722.6 (13.4)        | 39.0             |
| 128k           | 0               | 256    | 4096     | 114.5 | 104.9063 | 37524.3     | 2.1       | 98.9        | 30757.3 (240.2)      | 29.4             |
| 128k/80:4k/20  | 0               | 256    | 4096     | 163.6 | 193.5859 | 21170.3     | 2.0       | 98.5        | 463.0 (3.6)          | 25.7             |
| 128k/20:4k/80  | 0               | 256    | 4096     | 146.2 | 180.2087 | 6568.9      | 1.8       | 87.6        | 548.3 (4.2)          | 27.2             |
| 128k/80:8k/20  | 0               | 256    | 4096     | 157.3 | 193.7852 | 21649.9     | 2.0       | 98.3        | 713.3 (5.5)          | 29.9             |
| 128k/20:8k/80  | 0               | 256    | 4096     | 145.7 | 144.1413 | 7360.7      | 1.8       | 87.1        | 267.3 (2.0)          | 30.1             |
| 128k/80:16k/20 | 0               | 256    | 4096     | 159.7 | 107.6507 | 22196.4     | 2.1       | 98.9        | 439.3 (3.4)          | 25.8             |
| 128k/20:16k/80 | 0               | 256    | 4096     | 141.7 | 107.1408 | 9021.1      | 2.3       | 97.1        | 489.3 (3.8)          | 27.3             |
| 128k           | 4096            | 256    | 4096     | 125.1 | 103.3807 | 34314.3     | 2.3       | 99.1        | 15002.6 (117.2)      | 28.4             |
| 128k/80:4k/20  | 4096            | 256    | 4096     | 108.5 | 108.2401 | 31899.1     | 1.2       | 55.1        | 22832.0 (178.3)      | 30.6             |
| 128k/20:4k/80  | 4096            | 256    | 4096     | 101.3 | 106.1008 | 9392.2      | .8        | 52.6        | 11351.0 (88.6)       | 34.7             |
| 128k/80:16k/20 | 4096            | 256    | 4096     | 158.5 | 194.1746 | 22150.9     | 2.1       | 98.7        | 472.6 (3.6)          | 26.2             |
| 128k/20:16k/80 | 4096            | 256    | 4096     | 160.8 | 179.5518 | 8008.2      | 1.9       | 97.4        | 440.6 (3.4)          | 26.0             |
| 128k/80:8k/20  | 8192            | 256    | 4096     | 105.1 | 107.2975 | 33201.1     | .8        | 55.3        | 24286.6 (189.7)      | 34.8             |
| 128k/20:8k/80  | 8192            | 256    | 4096     | 100.5 | 106.8743 | 10672.8     | .4        | 53.8        | 7878.3 (61.5)        | 39.0             |
| 128k           | 16384           | 256    | 4096     | 141.3 | 182.7773 | 30399.4     | 2.5       | 99.1        | 14746.6 (115.2)      | 27.3             |
| 128k/80:4k/20  | 16384           | 256    | 4096     | 102.5 | 107.1555 | 33766.4     | .4        | 55.0        | 23423.6 (182.9)      | 31.1             |
| 128k/20:4k/80  | 16384           | 256    | 4096     | 101.6 | 105.6252 | 9499.8      | .5        | 52.8        | 3758.6 (29.3)        | 34.7             |
| 128k/80:16k/20 | 16384           | 256    | 4096     | 101.4 | 106.9899 | 34545.9     | .4        | 55.1        | 36422.6 (284.5)      | 34.7             |
| 128k/20:16k/80 | 16384           | 256    | 4096     | 100.5 | 106.3038 | 12811.7     | .2        | 53.8        | 14246.6 (111.3)      | 42.4             |

CPU mask 0xFFFF, IO pacer period 1500, adjusted period 24000, credit size 32768, num buffers 131072, buf cache 8192

| IO size        | Pacer threshold | QD/job | Total QD | BW    | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----------------|-----------------|--------|----------|-------|----------|-------------|-----------|-------------|----------------------|------------------|
| 128k           | 0               | 32     | 512       | 171.4 | 175.6714 | 3130.5      | .6        | 99.4        | 357.3 (2.7)          | 25.6             |
| 128k/80:4k/20  | 0               | 32     | 512       | 170.8 | 184.1124 | 2533.8      | .6        | 99.4        | 338.3 (2.6)          | 25.7             |
| 128k/20:4k/80  | 0               | 32     | 512       | 159.7 | 174.935  | 755.7       | .9        | 98.5        | 287.6 (2.2)          | 26.7             |
| 128k/80:16k/20 | 0               | 32     | 512       | 171.1 | 183.9553 | 2588.6      | .5        | 99.3        | 444.6 (3.4)          | 25.8             |
| 128k/20:16k/80 | 0               | 32     | 512       | 166.9 | 180.6896 | 963.9       | .8        | 98.9        | 323.3 (2.5)          | 26.0             |
| 128k           | 4096            | 32     | 512       | 171.0 | 184.0495 | 3138.7      | .6        | 99.4        | 346.6 (2.7)          | 25.7             |
| 128k/80:4k/20  | 4096            | 32     | 512       | 170.4 | 110.2542 | 2540.9      | .7        | 99.4        | 397.3 (3.1)          | 25.9             |
| 128k/20:4k/80  | 4096            | 32     | 512       | 159.8 | 165.3837 | 755.3       | 1.0       | 92.2        | 488.6 (3.8)          | 28.6             |
| 128k/80:16k/20 | 4096            | 32     | 512       | 170.5 | 183.5767 | 2596.5      | .7        | 99.4        | 364.0 (2.8)          | 25.7             |
| 128k/20:16k/80 | 4096            | 32     | 512       | 166.2 | 180.4854 | 968.1       | .9        | 98.9        | 280.0 (2.1)          | 26.1             |
| 128k           | 16384           | 32     | 512       | 171.0 | 184.081  | 3138.4      | .6        | 99.5        | 341.3 (2.6)          | 25.7             |
| 128k/80:4k/20  | 16384           | 32     | 512       | 172.3 | 184.9185 | 2511.6      | .7        | 99.4        | 414.0 (3.2)          | 25.6             |
| 128k/20:4k/80  | 16384           | 32     | 512       | 160.0 | 164.5103 | 754.2       | 1.0       | 89.9        | 468.6 (3.6)          | 28.6             |
| 128k/80:16k/20 | 16384           | 32     | 512       | 176.1 | 189.3841 | 2514.0      | .6        | 99.3        | 396.6 (3.0)          | 25.7             |
| 128k/20:16k/80 | 16384           | 32     | 512       | 148.3 | 161.101  | 1085.1      | .7        | 87.0        | 1492.6 (11.6)        | 38.7             |
| 128k           | 0               | 256    | 4096      | 159.3 | 184.1512 | 26691.2     | 1.3       | 99.1        | 384.0 (3.0)          | 26.6             |
| 128k/80:4k/20  | 0               | 256    | 4096      | 149.8 | 183.9489 | 23135.4     | 1.9       | 99.0        | 422.6 (3.3)          | 27.4             |
| 128k/20:4k/80  | 0               | 256    | 4096      | 166.6 | 174.7682 | 5724.3      | .6        | 97.3        | 436.3 (3.4)          | 26.6             |
| 128k/80:16k/20 | 0               | 256    | 4096      | 163.3 | 107.8718 | 21710.1     | 1.3       | 99.0        | 415.3 (3.2)          | 26.5             |
| 128k/20:16k/80 | 0               | 256    | 4096      | 168.4 | 184.1669 | 7557.9      | .5        | 98.3        | 377.3 (2.9)          | 26.2             |
| 128k           | 4096            | 256    | 4096      | 166.6 | 184.0484 | 25801.2     | .6        | 80.7        | 405.3 (3.1)          | 26.2             |
| 128k/80:4k/20  | 4096            | 256    | 4096      | 156.0 | 183.6634 | 22199.6     | 1.8       | 99.0        | 409.3 (3.1)          | 27.2             |
| 128k/20:4k/80  | 4096            | 256    | 4096      | 104.2 | 139.5398 | 9142.0      | 1.0       | 58.1        | 354.3 (2.7)          | 34.5             |
| 128k/80:16k/20 | 4096            | 256    | 4096      | 169.5 | 181.5296 | 20908.1     | .6        | 94.6        | 395.3 (3.0)          | 26.0             |
| 128k/20:16k/80 | 4096            | 256    | 4096      | 170.7 | 183.4849 | 7544.4      | .6        | 98.3        | 359.3 (2.8)          | 26.1             |
| 128k           | 16384           | 256    | 4096      | 142.9 | 183.975  | 29889.0     | 2.1       | 57.3        | 13632.0 (106.5)      | 27.9             |
| 128k/80:4k/20  | 16384           | 256    | 4096      | 157.3 | 156.139  | 22114.3     | 1.9       | 99.0        | 455.6 (3.5)          | 27.1             |
| 128k/20:4k/80  | 16384           | 256    | 4096      | 106.6 | 106.1473 | 9053.6      | 1.0       | 55.8        | 8321.6 (65.0)        | 34.4             |
| 128k/80:16k/20 | 16384           | 256    | 4096      | 149.8 | 189.501  | 23653.2     | 2.1       | 98.9        | 425.3 (3.3)          | 27.8             |
| 128k/20:16k/80 | 16384           | 256    | 4096      | 99.7  | 107.5674 | 12804.1     | .3        | 54.1        | 14587.3 (113.9)      | 43.2             |

#### Bufs-in-flight based tuner

CPU mask 0xFFFF, IO pacer period 2875, adjusted period 46000, credit size 65536, num buffers 131072, buf cache 8192

| IO size        | Pacer threshold | QD/job | Total QD | BW    | BW Max | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us |
|----------------|-----------------|--------|----------|-------|--------|----------|-------------|-----------|-------------|----------------------|------------------|
| 128k           | 0               | 32     | 512      | 177.9 | 186.5  | 192.532  | 3017.4      | .7        | 99.4        | 149.3 (1.1)          | 46.8             |
| 128k           | 0               | 64     | 1024     | 177.2 | 188.0  | 191.318  | 6057.7      | .7        | 99.4        | 1429.3 (11.1)        | 46.8             |
| 128k           | 0               | 128    | 2048     | 175.3 | 195.6  | 192.9416 | 12137.6     | .7        | 99.3        | 208.0 (1.6)          | 46.9             |
| 128k           | 0               | 256    | 4096     | 163.9 | 186.6  | 192.0799 | 26195.0     | 1.5       | 99.2        | 250.6 (1.9)          | 47.3             |
| 4k             | 0               | 32     | 512      | 106.6 | 128.0  | 119.758  | 157.1       | .5        | 94.4        | 63.6 (.4)            | 46.8             |
| 4k             | 0               | 64     | 1024     | 130.0 | 156.6  | 144.8835 | 257.9       | .5        | 94.0        | 245.0 (1.9)          | 50.9             |
| 4k             | 0               | 128    | 2048     | 122.6 | 151.3  | 136.992  | 546.7       | .5        | 93.8        | 239.0 (1.8)          | 52.0             |
| 4k             | 0               | 256    | 4096     | 121.5 | 150.8  | 130.038  | 1103.8      | .5        | 93.8        | 349.3 (2.7)          | 52.6             |
| 128k/80:4k/20  | 0               | 32     | 512      | 177.6 | 188.0  | 191.6029 | 2436.0      | .7        | 99.3        | 161.0 (1.2)          | 46.7             |
| 128k/80:4k/20  | 0               | 64     | 1024     | 179.2 | 184.9  | 192.0138 | 4829.8      | .5        | 99.2        | 299.3 (2.3)          | 46.8             |
| 128k/80:4k/20  | 0               | 128    | 2048     | 175.1 | 185.8  | 192.2844 | 9687.4      | .5        | 99.0        | 285.0 (2.2)          | 46.8             |
| 128k/80:4k/20  | 0               | 256    | 4096     | 179.6 | 188.1  | 192.3728 | 19282.5     | .4        | 98.8        | 306.0 (2.3)          | 46.8             |
| 128k/20:4k/80  | 0               | 32     | 512      | 173.2 | 183.2  | 187.5099 | 696.5       | .6        | 98.5        | 201.6 (1.5)          | 46.6             |
| 128k/20:4k/80  | 0               | 64     | 1024     | 176.5 | 184.1  | 190.8313 | 1367.4      | .5        | 98.0        | 294.6 (2.3)          | 46.7             |
| 128k/20:4k/80  | 0               | 128    | 2048     | 177.2 | 185.9  | 191.7881 | 2724.2      | .6        | 97.2        | 354.0 (2.7)          | 46.7             |
| 128k/20:4k/80  | 0               | 256    | 4096     | 172.8 | 186.5  | 189.5838 | 5509.5      | .5        | 96.7        | 364.6 (2.8)          | 46.9             |
| 8k             | 0               | 32     | 512      | 174.8 | 183.3  | 192.552  | 191.6       | .7        | 96.7        | 99.0 (.7)            | 46.8             |
| 8k             | 0               | 64     | 1024     | 177.2 | 182.4  | 193.945  | 378.4       | .6        | 96.6        | 108.0 (.8)           | 46.7             |
| 8k             | 0               | 128    | 2048     | 177.3 | 181.8  | 194.119  | 756.3       | .6        | 96.5        | 116.3 (.9)           | 46.7             |
| 8k             | 0               | 256    | 4096     | 176.0 | 181.6  | 193.9613 | 1524.6      | .6        | 96.4        | 158.0 (1.2)          | 46.8             |
| 128k/80:8k/20  | 0               | 32     | 512      | 178.1 | 185.5  | 192.376  | 2448.3      | .6        | 99.4        | 112.0 (.8)           | 46.7             |
| 128k/80:8k/20  | 0               | 64     | 1024     | 179.3 | 186.0  | 192.0918 | 4864.6      | .5        | 99.2        | 263.0 (2.0)          | 46.8             |
| 128k/80:8k/20  | 0               | 128    | 2048     | 174.2 | 186.0  | 192.4271 | 9756.7      | .5        | 99.1        | 294.0 (2.2)          | 46.9             |
| 128k/80:8k/20  | 0               | 256    | 4096     | 166.7 | 184.8  | 192.4183 | 20501.2     | 1.1       | 99.2        | 322.3 (2.5)          | 47.2             |
| 128k/20:8k/80  | 0               | 32     | 512      | 173.8 | 186.0  | 189.1566 | 771.5       | .7        | 98.7        | 100.6 (.7)           | 46.7             |
| 128k/20:8k/80  | 0               | 64     | 1024     | 177.4 | 184.5  | 191.1789 | 1512.0      | .5        | 98.4        | 289.0 (2.2)          | 46.7             |
| 128k/20:8k/80  | 0               | 128    | 2048     | 178.1 | 187.0  | 191.2498 | 3012.7      | .5        | 97.8        | 323.3 (2.5)          | 46.7             |
| 128k/20:8k/80  | 0               | 256    | 4096     | 174.3 | 184.9  | 192.7867 | 6038.3      | .5        | 97.1        | 301.0 (2.3)          | 46.8             |
| 16k            | 0               | 32     | 512      | 176.7 | 191.8  | 193.4846 | 379.4       | .8        | 98.2        | 69.3 (.5)            | 46.6             |
| 16k            | 0               | 64     | 1024     | 178.6 | 182.6  | 193.5834 | 751.1       | .5        | 98.2        | 88.6 (.6)            | 46.6             |
| 16k            | 0               | 128    | 2048     | 178.6 | 186.7  | 193.5297 | 1502.4      | .5        | 98.1        | 116.6 (.9)           | 46.6             |
| 16k            | 0               | 256    | 4096     | 178.6 | 183.5  | 193.8034 | 3004.3      | .5        | 98.1        | 116.6 (.9)           | 46.6             |
| 128k/80:16k/20 | 0               | 32     | 512      | 173.1 | 186.3  | 131.6063 | 2558.3      | 1.1       | 99.3        | 145.3 (1.1)          | 47.2             |
| 128k/80:16k/20 | 0               | 64     | 1024     | 179.2 | 185.5  | 192.3057 | 4940.9      | .5        | 99.3        | 268.0 (2.0)          | 47.0             |
| 128k/80:16k/20 | 0               | 128    | 2048     | 177.6 | 185.1  | 192.4288 | 9974.8      | .7        | 99.1        | 290.0 (2.2)          | 47.0             |
| 128k/80:16k/20 | 0               | 256    | 4096     | 175.9 | 186.0  | 192.6398 | 19897.4     | .4        | 99.0        | 274.6 (2.1)          | 47.0             |
| 128k/20:16k/80 | 0               | 32     | 512      | 176.8 | 183.5  | 190.2732 | 909.8       | .5        | 98.9        | 182.6 (1.4)          | 46.6             |
| 128k/20:16k/80 | 0               | 64     | 1024     | 178.1 | 185.6  | 191.621  | 1806.7      | .5        | 98.7        | 210.6 (1.6)          | 46.6             |
| 128k/20:16k/80 | 0               | 128    | 2048     | 178.5 | 185.1  | 192.2229 | 3605.6      | .5        | 98.3        | 220.6 (1.7)          | 46.7             |
| 128k/20:16k/80 | 0               | 256    | 4096     | 174.4 | 222.6  | 192.0465 | 7271.9      | .8        | 97.7        | 240.0 (1.8)          | 46.8             |
| 128k           | 16384           | 32     | 512      | 177.9 | 187.5  | 192.5968 | 3016.8      | .7        | 99.5        | 85.3 (.6)            | 46.8             |
| 128k           | 16384           | 64     | 1024     | 179.5 | 184.2  | 192.4776 | 5978.6      | .5        | 99.4        | 229.3 (1.7)          | 46.8             |
| 128k           | 16384           | 128    | 2048     | 164.7 | 185.4  | 192.9989 | 13038.5     | 1.7       | 99.3        | 240.0 (1.8)          | 47.4             |
| 128k           | 16384           | 256    | 4096     | 157.5 | 182.8  | 192.573  | 27254.4     | 1.8       | 98.7        | 272.0 (2.1)          | 48.0             |
| 4k             | 16384           | 32     | 512      | 110.6 | 116.4  | 121.7208 | 151.3       | .4        | 94.5        | 318.0 (2.4)          | 48.9             |
| 4k             | 16384           | 64     | 1024     | 130.6 | 155.7  | 145.2908 | 256.6       | .5        | 93.6        | 328.3 (2.5)          | 56.4             |
| 4k             | 16384           | 128    | 2048     | 123.7 | 150.3  | 137.386  | 542.2       | .5        | 91.3        | 627.0 (4.8)          | 60.8             |
| 4k             | 16384           | 256    | 4096     | 120.0 | 150.3  | 134.4174 | 1117.3      | .5        | 90.1        | 1496.6 (11.6)        | 63.2             |
| 128k/80:4k/20  | 16384           | 32     | 512      | 180.5 | 184.9  | 193.5752 | 2397.9      | .5        | 99.2        | 295.6 (2.3)          | 47.1             |
| 128k/80:4k/20  | 16384           | 64     | 1024     | 175.1 | 185.8  | 193.4736 | 4943.8      | .9        | 99.1        | 264.3 (2.0)          | 47.3             |
| 128k/80:4k/20  | 16384           | 128    | 2048     | 179.8 | 186.3  | 194.1539 | 9628.8      | .5        | 98.9        | 315.6 (2.4)          | 47.2             |
| 128k/80:4k/20  | 16384           | 256    | 4096     | 181.0 | 188.9  | 194.0241 | 19136.0     | .4        | 98.6        | 328.0 (2.5)          | 47.1             |
| 128k/20:4k/80  | 16384           | 32     | 512      | 163.6 | 183.6  | 178.2513 | 737.4       | .6        | 91.0        | 382.3 (2.9)          | 50.2             |
| 128k/20:4k/80  | 16384           | 64     | 1024     | 160.3 | 183.8  | 169.6218 | 1506.4      | .6        | 89.5        | 640.3 (5.0)          | 50.6             |
| 128k/20:4k/80  | 16384           | 128    | 2048     | 160.8 | 189.8  | 172.6404 | 3002.8      | .7        | 89.9        | 566.6 (4.4)          | 51.0             |
| 128k/20:4k/80  | 16384           | 256    | 4096     | 159.0 | 200.8  | 163.5842 | 6072.6      | 1.2       | 90.7        | 537.6 (4.2)          | 51.4             |
| 8k             | 16384           | 32     | 512      | 180.5 | 195.4  | 195.2258 | 185.6       | .8        | 96.7        | 82.3 (.6)            | 50.6             |
| 8k             | 16384           | 64     | 1024     | 182.3 | 234.0  | 195.4598 | 376.3       | 1.0       | 93.2        | 329.6 (2.5)          | 48.8             |
| 8k             | 16384           | 128    | 2048     | 121.7 | 159.5  | 129.8098 | 1102.2      | .5        | 65.3        | 856.0 (6.6)          | 52.1             |
| 8k             | 16384           | 256    | 4096     | 104.9 | 146.2  | 110.0847 | 2557.1      | .5        | 58.5        | 1913.3 (14.9)        | 56.5             |
| 128k/80:8k/20  | 16384           | 32     | 512      | 179.5 | 186.0  | 195.3507 | 2429.6      | .8        | 98.7        | 291.6 (2.2)          | 46.9             |
| 128k/80:8k/20  | 16384           | 64     | 1024     | 181.6 | 186.2  | 195.3626 | 4804.1      | .5        | 98.1        | 279.3 (2.1)          | 46.9             |
| 128k/80:8k/20  | 16384           | 128    | 2048     | 181.0 | 187.5  | 195.2606 | 9639.0      | .4        | 97.9        | 322.6 (2.5)          | 47.0             |
| 128k/80:8k/20  | 16384           | 256    | 4096     | 174.2 | 188.1  | 192.6874 | 19556.2     | .5        | 97.4        | 316.6 (2.4)          | 47.1             |
| 128k/20:8k/80  | 16384           | 32     | 512      | 175.5 | 185.7  | 190.143  | 764.1       | .6        | 96.0        | 423.6 (3.3)          | 50.6             |
| 128k/20:8k/80  | 16384           | 64     | 1024     | 161.2 | 185.2  | 173.5152 | 1663.3      | 1.3       | 95.5        | 421.3 (3.2)          | 52.8             |
| 128k/20:8k/80  | 16384           | 128    | 2048     | 146.5 | 184.7  | 134.8003 | 3661.9      | 1.5       | 94.9        | 470.6 (3.6)          | 54.8             |
| 128k/20:8k/80  | 16384           | 256    | 4096     | 136.2 | 178.1  | 156.5576 | 7738.4      | .7        | 75.3        | 1454.3 (11.3)        | 56.4             |
| 16k            | 16384           | 32     | 512      | 183.0 | 196.9  | 196.0165 | 366.4       | .8        | 95.5        | 196.6 (1.5)          | 60.3             |
| 16k            | 16384           | 64     | 1024     | 132.1 | 165.3  | 137.694  | 1015.0      | .6        | 68.4        | 795.3 (6.2)          | 60.1             |
| 16k            | 16384           | 128    | 2048     | 110.1 | 152.3  | 116.1409 | 2437.8      | .5        | 60.8        | 2420.6 (18.9)        | 64.3             |
| 16k            | 16384           | 256    | 4096     | 103.7 | 149.5  | 110.3241 | 5176.5      | .5        | 57.2        | 3512.6 (27.4)        | 68.3             |
| 128k/80:16k/20 | 16384           | 32     | 512      | 163.3 | 185.8  | 173.1535 | 2712.3      | .7        | 92.4        | 124.0 (.9)           | 49.5             |
| 128k/80:16k/20 | 16384           | 64     | 1024     | 157.6 | 185.0  | 166.4684 | 5620.1      | .7        | 90.3        | 307.3 (2.4)          | 50.6             |
| 128k/80:16k/20 | 16384           | 128    | 2048     | 157.7 | 182.6  | 159.8106 | 11236.9     | .6        | 91.5        | 520.0 (4.0)          | 51.1             |
| 128k/80:16k/20 | 16384           | 256    | 4096     | 158.8 | 189.8  | 168.8271 | 22317.8     | .7        | 86.9        | 372.0 (2.9)          | 51.2             |
| 128k/20:16k/80 | 16384           | 32     | 512      | 166.2 | 179.7  | 170.8907 | 967.2       | .9        | 98.2        | 183.3 (1.4)          | 54.1             |
| 128k/20:16k/80 | 16384           | 64     | 1024     | 124.7 | 180.5  | 120.8951 | 2541.2      | 1.5       | 60.1        | 1316.0 (10.2)        | 59.2             |
| 128k/20:16k/80 | 16384           | 128    | 2048     | 110.4 | 166.2  | 115.1146 | 5829.8      | .6        | 57.3        | 3441.3 (26.8)        | 63.8             |
| 128k/20:16k/80 | 16384           | 256    | 4096     | 107.2 | 165.0  | 114.5265 | 11741.6     | .7        | 56.6        | 2714.0 (21.2)        | 66.7             |

#### With 4k latencies

Bufs-in-flight based tuner.

CPU mask 0xFFFF, IO pacer period 2875, adjusted period 46000, credit size 65536, num buffers 131072, buf cache 8192.

| IO size       | Pacer period | Pacer threshold | QD/job | Total QD | BW    | BW Max | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us | Req lat small, us | Req lat large, us | Req lat, us |
|---------------|--------------|-----------------|--------|----------|-------|--------|----------|-------------|-----------|-------------|----------------------|------------------|-------------------|-------------------|-------------|
| 128k          | 0            | 0               | 16     | 256      | 112.3 | 149.2  | 118.7157 | 2388.0      | .5        | 60.6        | 1125.3 (8.7)         |                  | 2.69056           | 2369.6            | 2369.59     |
| 128k          | 0            | 0               | 32     | 512      | 107.4 | 151.6  | 113.9509 | 4998.1      | .4        | 58.8        | 2661.3 (20.7)        |                  | 3.14459           | 5012.18           | 5012.16     |
| 128k          | 0            | 0               | 256    | 4096     | 95.5  | 146.4  | 104.6467 | 44294.4     | .4        | 57.4        | 35765.3 (279.4)      |                  | 4.76547           | 35113.1           | 35112.9     |
| 4k            | 0            | 0               | 16     | 256      | 89.9  | 95.2   | 100.6637 | 92.9        | .3        | 95.0        | 58.6 (.4)            |                  | 72.5353           | 0                 | 72.5353     |
| 4k            | 0            | 0               | 32     | 512      | 117.9 | 144.3  | 129.0263 | 142.0       | .4        | 94.5        | 180.6 (1.4)          |                  | 148.556           | 0                 | 148.556     |
| 4k            | 0            | 0               | 256    | 4096     | 124.7 | 153.3  | 138.8947 | 1075.2      | .5        | 90.6        | 1401.6 (10.9)        |                  | 658.473           | 0                 | 658.473     |
| 128k/80:4k/20 | 0            | 0               | 16     | 256      | 114.9 | 155.6  | 120.1925 | 1882.2      | .5        | 59.8        | 971.6 (7.5)          |                  | 1645.05           | 1922.27           | 1866.86     |
| 128k/80:4k/20 | 0            | 0               | 32     | 512      | 108.2 | 149.4  | 114.4265 | 3999.1      | .4        | 56.7        | 4247.0 (33.1)        |                  | 3743.56           | 4038.89           | 3979.86     |
| 128k/80:4k/20 | 0            | 0               | 256    | 4096     | 101.7 | 146.7  | 107.8295 | 34051.4     | .4        | 55.0        | 21993.0 (171.8)      |                  | 26342.7           | 26633.7           | 26575.5     |
| 128k/20:4k/80 | 0            | 0               | 16     | 256      | 181.2 | 193.4  | 195.1329 | 332.7       | .7        | 95.2        | 208.0 (1.6)          |                  | 301.896           | 443.433           | 330.191     |
| 128k/20:4k/80 | 0            | 0               | 32     | 512      | 126.5 | 161.8  | 134.0633 | 953.2       | .5        | 63.1        | 729.6 (5.7)          |                  | 896.438           | 1137.54           | 944.614     |
| 128k/20:4k/80 | 0            | 0               | 256    | 4096     | 100.9 | 139.6  | 108.952  | 9569.0      | .3        | 50.8        | 8671.0 (67.7)        |                  | 7098.6            | 7404.29           | 7159.68     |
| 128k/3:4k/97  | 0            | 0               | 16     | 256      | 135.1 | 149.5  | 148.8295 | 119.5       | .5        | 96.4        | 140.6 (1.0)          |                  | 119.783           | 212.847           | 122.577     |
| 128k/3:4k/97  | 0            | 0               | 32     | 512      | 166.8 | 176.7  | 182.1198 | 193.8       | .6        | 95.6        | 362.6 (2.8)          |                  | 196.162           | 298.846           | 199.243     |
| 128k/3:4k/97  | 0            | 0               | 256    | 4096     | 97.2  | 143.0  | 106.4722 | 2628.3      | .5        | 52.5        | 2782.0 (21.7)        |                  | 1992.49           | 2274.32           | 2000.95     |
| 128k          | 2875         | 0               | 16     | 256      | 178.2 | 184.5  | 192.3901 | 1505.8      | .6        | 99.5        | 202.6 (1.5)          | 46.8             | 1.09837           | 1499.78           | 1499.78     |
| 128k          | 2875         | 0               | 32     | 512      | 179.2 | 184.2  | 192.4418 | 2995.1      | .5        | 99.5        | 240.0 (1.8)          | 46.4             | 1.24759           | 2990.74           | 2990.73     |
| 128k          | 2875         | 0               | 256    | 4096     | 176.5 | 187.4  | 192.7698 | 24339.4     | .8        | 99.2        | 266.6 (2.0)          | 46.4             | 1.50219           | 14545.7           | 14545.6     |
| 4k            | 2875         | 0               | 16     | 256      |       |        | 95.5     | 51.0        | 31.3      |             |                      |                  | 82.6835           | 0                 | 82.6835     |
| 4k            | 2875         | 0               | 32     | 512      | 109.0 | 133.2  | 120.4675 | 153.6       | .3        | 94.3        | 133.0 (1.0)          | 47.6             | 159.192           | 0                 | 159.192     |
| 4k            | 2875         | 0               | 256    | 4096     | 120.3 | 150.0  | 133.5552 | 1114.7      | .4        | 93.7        | 352.3 (2.7)          | 48.2             | 672.184           | 0                 | 672.184     |
| 128k/80:4k/20 | 2875         | 0               | 16     | 256      | 177.2 | 188.1  | 191.6332 | 1220.9      | .7        | 99.4        | 520.0 (4.0)          | 46.7             | 1108.91           | 1238.63           | 1212.7      |
| 128k/80:4k/20 | 2875         | 0               | 32     | 512      | 179.1 | 185.7  | 192.1925 | 2416.2      | .5        | 99.3        | 310.0 (2.4)          | 46.4             | 2302.36           | 2437.17           | 2410.23     |
| 128k/80:4k/20 | 2875         | 0               | 256    | 4096     | 169.5 | 183.7  | 192.3465 | 20095.8     | .7        | 98.9        | 305.6 (2.3)          | 46.5             | 13740.5           | 13916.5           | 13881.3     |
| 128k/20:4k/80 | 2875         | 0               | 16     | 256      | 165.8 | 179.8  | 178.8094 | 363.7       | .7        | 98.7        | 77.3 (.6)            | 46.6             | 338.433           | 449.938           | 360.726     |
| 128k/20:4k/80 | 2875         | 0               | 32     | 512      | 174.0 | 181.5  | 187.6293 | 693.5       | .5        | 98.5        | 241.6 (1.8)          | 46.3             | 665.947           | 785.907           | 689.929     |
| 128k/20:4k/80 | 2875         | 0               | 256    | 4096     | 172.4 | 208.3  | 189.686  | 5561.5      | .7        | 96.1        | 336.0 (2.6)          | 46.5             | 3969.7            | 4103.18           | 3996.38     |
| 128k/3:4k/97  | 2875         | 0               | 16     | 256      | 113.9 | 130.6  | 125.1711 | 141.9       | .5        | 96.5        | 55.0 (.4)            | 46.6             | 140.325           | 230.676           | 143.037     |
| 128k/3:4k/97  | 2875         | 0               | 32     | 512      | 148.4 | 165.9  | 162.6125 | 218.0       | .4        | 96.0        | 123.3 (.9)           | 46.4             | 218.097           | 308.777           | 220.817     |
| 128k/3:4k/97  | 2875         | 0               | 256    | 4096     | 164.0 | 180.4  | 180.1487 | 1578.8      | .6        | 94.2        | 299.3 (2.3)          | 46.7             | 1078.78           | 1162.7            | 1081.29     |
| 128k          | 2875         | 16384           | 16     | 256      | 177.8 | 186.3  | 192.5783 | 1509.0      | .7        | 99.5        | 522.6 (4.0)          | 46.7             | 1.18712           | 1502.53           | 1502.53     |
| 128k          | 2875         | 16384           | 32     | 512      | 179.4 | 184.6  | 192.5964 | 2991.9      | .5        | 99.5        | 256.0 (2.0)          | 46.4             | 1.20406           | 2987.34           | 2987.33     |
| 128k          | 2875         | 16384           | 256    | 4096     | 172.7 | 187.9  | 192.7291 | 24874.8     | 1.1       | 99.2        | 261.3 (2.0)          | 46.5             | 1.29475           | 15536.4           | 15536.4     |
| 4k            | 2875         | 16384           | 16     | 256      | 90.4  | 110.6  | 101.0247 | 92.5        | .4        | 94.7        | 41.6 (.3)            | 46.7             | 95.3616           | 0                 | 95.3616     |
| 4k            | 2875         | 16384           | 32     | 512      | 116.9 | 143.2  | 129.3802 | 143.2       | .4        | 94.5        | 169.6 (1.3)          | 46.7             | 149.46            | 0                 | 149.46      |
| 4k            | 2875         | 16384           | 256    | 4096     | 125.3 | 151.4  | 138.0555 | 1070.5      | .5        | 90.4        | 1462.6 (11.4)        | 49.5             | 659.929           | 0                 | 659.929     |
| 128k/80:4k/20 | 2875         | 16384           | 16     | 256      | 178.7 | 185.0  | 193.0626 | 1210.5      | .7        | 99.3        | 135.0 (1.0)          | 46.7             | 139.779           | 1469.21           | 1203.51     |
| 128k/80:4k/20 | 2875         | 16384           | 32     | 512      | 180.4 | 185.0  | 193.6073 | 2398.5      | .5        | 99.2        | 273.6 (2.1)          | 46.4             | 154.571           | 2954.48           | 2394.89     |
| 128k/80:4k/20 | 2875         | 16384           | 256    | 4096     | 161.6 | 188.1  | 66.9552  | 20823.5     | 1.5       | 98.7        | 306.3 (2.3)          | 46.7             | 226.528           | 17131.3           | 13753.6     |
| 128k/20:4k/80 | 2875         | 16384           | 16     | 256      | 182.5 | 195.3  | 195.888  | 330.3       | .8        | 95.0        | 300.0 (2.3)          | 46.7             | 228.5             | 724.342           | 327.631     |
| 128k/20:4k/80 | 2875         | 16384           | 32     | 512      | 164.3 | 187.3  | 175.6448 | 734.2       | .6        | 90.9        | 502.6 (3.9)          | 47.3             | 253.496           | 2650.56           | 732.735     |
| 128k/20:4k/80 | 2875         | 16384           | 256    | 4096     | 155.9 | 199.2  | 169.3597 | 6197.1      | 1.0       | 89.7        | 465.3 (3.6)          | 47.9             | 335.107           | 17713             | 3811.75     |
| 128k/3:4k/97  | 2875         | 16384           | 16     | 256      | 135.0 | 153.7  | 147.935  | 119.6       | .4        | 96.4        | 183.6 (1.4)          | 46.7             | 118.723           | 256.849           | 122.869     |
| 128k/3:4k/97  | 2875         | 16384           | 32     | 512      | 165.4 | 181.2  | 181.9813 | 195.3       | .6        | 95.5        | 262.3 (2.0)          | 46.6             | 194.966           | 361.368           | 199.959     |
| 128k/3:4k/97  | 2875         | 16384           | 256    | 4096     | 96.0  | 155.3  | 104.6476 | 2626.1      | .6        | 52.4        | 2649.3 (20.6)        | 50.8             | 1613.19           | 18095.7           | 2108.41     |

#### With 8k latencies

Bufs-in-flight based tuner.

CPU mask 0xFFFF, IO pacer period 2875, adjusted period 46000, credit size 65536, num buffers 131072, buf cache 8192.

| IO size       | Pacer period | Pacer threshold | QD/job | Total QD | BW    | BW Max | WIRE BW  | AVG LAT, us | BW STDDEV | L3 Hit Rate | Bufs in-flight (MiB) | Pacer period, us | Req lat small, us | Req lat large, us | Req lat, us |
|---------------|--------------|-----------------|--------|----------|-------|--------|----------|-------------|-----------|-------------|----------------------|------------------|-------------------|-------------------|-------------|
| 8k            | 0            | 0               | 16     | 256      | 168.3 | 176.6  | 185.0136 | 99.5        | .7        | 97.0        | 42.3 (.3)            |                  | 101.375           | 0                 | 101.375     |
| 8k            | 0            | 0               | 32     | 512      | 180.8 | 193.4  | 195.2677 | 185.3       | .5        | 96.8        | 170.0 (1.3)          |                  | 187.222           | 0                 | 187.222     |
| 8k            | 0            | 0               | 256    | 4096     | 106.6 | 152.1  | 110.7358 | 2516.1      | .5        | 58.2        | 1936.3 (15.1)        |                  | 1895.8            | 0                 | 1895.8      |
| 128k/80:8k/20 | 0            | 0               | 16     | 256      | 114.9 | 153.7  | 122.481  | 1896.5      | .5        | 60.1        | 890.3 (6.9)          |                  | 1665.19           | 1935.65           | 1881.59     |
| 128k/80:8k/20 | 0            | 0               | 32     | 512      | 108.0 | 148.7  | 114.0633 | 4036.9      | .4        | 56.6        | 2159.3 (16.8)        |                  | 3793.65           | 4079.81           | 4022.61     |
| 128k/80:8k/20 | 0            | 0               | 256    | 4096     | 99.1  | 138.5  | 107.9583 | 34466.9     | .3        | 55.2        | 29527.0 (230.6)      |                  | 27054.1           | 27317.4           | 27264.7     |
| 128k/20:8k/80 | 0            | 0               | 16     | 256      | 180.8 | 194.2  | 193.7988 | 370.6       | .7        | 92.0        | 191.6 (1.4)          |                  | 337.567           | 486.863           | 367.415     |
| 128k/20:8k/80 | 0            | 0               | 32     | 512      | 125.2 | 156.7  | 132.0584 | 1071.1      | .5        | 63.3        | 889.3 (6.9)          |                  | 1013.26           | 1253.66           | 1061.3      |
| 128k/20:8k/80 | 0            | 0               | 256    | 4096     | 98.8  | 144.4  | 108.1703 | 10585.5     | .4        | 52.8        | 8681.6 (67.8)        |                  | 7859.41           | 8155.49           | 7918.55     |
| 128k/3:8k/97  | 0            | 0               | 16     | 256      | 98.8  | 144.4  | 0        | 10585.5     | .4        | 99.8        | 0 (0)                |                  | 0                 | 0                 | 0           |
| 128k/3:8k/97  | 0            | 0               | 32     | 512      | 181.2 | 193.9  | 195.6476 | 268.1       | .6        | 95.8        | 266.0 (2.0)          |                  | 263.399           | 415.541           | 267.967     |
| 128k/3:8k/97  | 0            | 0               | 256    | 4096     | 101.6 | 140.9  | 107.4974 | 3828.8      | .4        | 55.1        | 2822.0 (22.0)        |                  | 2875.02           | 3160.04           | 2883.57     |
| 8k            | 2875         | 0               | 16     | 256      | 135.7 | 154.4  | 148.1109 | 123.5       | .5        | 96.9        | 29.3 (.2)            | 46.6             | 124.863           | 0                 | 124.863     |
| 8k            | 2875         | 0               | 32     | 512      | 175.9 | 182.8  | 192.7047 | 190.4       | .6        | 96.7        | 49.6 (.3)            | 46.4             | 191.062           | 0                 | 191.062     |
| 8k            | 2875         | 0               | 256    | 4096     | 176.9 | 181.9  | 193.9464 | 1516.8      | .6        | 96.4        | 168.6 (1.3)          | 46.4             | 1013.02           | 0                 | 1013.02     |
| 128k/80:8k/20 | 2875         | 0               | 16     | 256      | 177.1 | 188.6  | 191.8535 | 1231.1      | .7        | 99.4        | 128.3 (1.0)          | 46.7             | 1122.31           | 1248.62           | 1223.37     |
| 128k/80:8k/20 | 2875         | 0               | 32     | 512      | 179.1 | 184.2  | 191.9081 | 2435.1      | .5        | 99.4        | 252.3 (1.9)          | 46.4             | 2323.4            | 2456.15           | 2429.61     |
| 128k/80:8k/20 | 2875         | 0               | 256    | 4096     | 169.2 | 184.2  | 192.5074 | 20362.2     | 1.1       | 98.9        | 280.3 (2.1)          | 46.6             | 13235.3           | 13374.9           | 13347       |
| 128k/20:8k/80 | 2875         | 0               | 16     | 256      | 168.1 | 199.4  | 183.061  | 397.8       | .8        | 98.8        | 78.6 (.6)            | 46.6             | 371.61            | 484.373           | 394.159     |
| 128k/20:8k/80 | 2875         | 0               | 32     | 512      | 175.3 | 183.2  | 189.1485 | 764.7       | .5        | 98.7        | 206.3 (1.6)          | 46.3             | 736.02            | 857.75            | 760.359     |
| 128k/20:8k/80 | 2875         | 0               | 256    | 4096     | 177.4 | 185.8  | 190.1715 | 6046.8      | .6        | 97.4        | 341.0 (2.6)          | 46.4             | 4300.61           | 4424.42           | 4325.36     |
| 128k/3:8k/97  | 2875         | 0               | 16     | 256      | 148.4 | 167.3  | 162.6923 | 163.6       | .6        | 97.5        | 32.6 (.2)            | 46.6             | 160.118           | 261.303           | 163.155     |
| 128k/3:8k/97  | 2875         | 0               | 32     | 512      | 170.5 | 181.5  | 185.4619 | 285.1       | .5        | 97.4        | 103.3 (.8)           | 46.4             | 280.852           | 399.334           | 284.409     |
| 128k/3:8k/97  | 2875         | 0               | 256    | 4096     | 171.5 | 184.5  | 193.0425 | 2269.3      | 1.1       | 96.1        | 207.0 (1.6)          | 46.5             | 1668.53           | 1813.99           | 1672.9      |
| 8k            | 2875         | 16384           | 16     | 256      | 167.5 | 183.4  | 184.2129 | 100.0       | .6        | 96.9        | 42.3 (.3)            | 46.7             | 101.883           | 0                 | 101.883     |
| 8k            | 2875         | 16384           | 32     | 512      | 180.5 | 195.2  | 194.9618 | 185.6       | .7        | 96.7        | 166.3 (1.2)          | 46.4             | 187.444           | 0                 | 187.444     |
| 8k            | 2875         | 16384           | 256    | 4096     | 105.4 | 143.6  | 115.8184 | 2545.5      | .5        | 60.2        | 1902.3 (14.8)        | 49.8             | 1931.94           | 0                 | 1931.94     |
| 128k/80:8k/20 | 2875         | 16384           | 16     | 256      | 180.1 | 187.3  | 195.066  | 1210.6      | .7        | 99.3        | 150.6 (1.1)          | 46.7             | 161.517           | 1464.4            | 1203.98     |
| 128k/80:8k/20 | 2875         | 16384           | 32     | 512      | 181.4 | 185.7  | 194.9882 | 2404.4      | .5        | 98.6        | 306.3 (2.3)          | 46.4             | 195.178           | 2949.54           | 2399.22     |
| 128k/80:8k/20 | 2875         | 16384           | 256    | 4096     | 180.5 | 187.0  | 194.9563 | 19332.1     | .4        | 97.2        | 287.0 (2.2)          | 46.4             | 258.728           | 17712.7           | 14225.5     |
| 128k/20:8k/80 | 2875         | 16384           | 16     | 256      | 182.5 | 194.8  | 195.708  | 367.1       | .7        | 93.1        | 368.6 (2.8)          | 47.2             | 286.976           | 670.098           | 363.581     |
| 128k/20:8k/80 | 2875         | 16384           | 32     | 512      | 175.8 | 186.0  | 186.9796 | 762.6       | .5        | 96.6        | 331.3 (2.5)          | 47.6             | 262.334           | 2749.36           | 759.683     |
| 128k/20:8k/80 | 2875         | 16384           | 256    | 4096     | 139.0 | 181.4  | 155.3423 | 7718.8      | .7        | 75.8        | 706.0 (5.5)          | 49.2             | 872.709           | 24549.3           | 5606.58     |
| 128k/3:8k/97  | 2875         | 16384           | 16     | 256      | 170.7 | 187.6  | 187.083  | 142.1       | .7        | 97.3        | 104.3 (.8)           | 46.7             | 137.918           | 298.372           | 142.734     |
| 128k/3:8k/97  | 2875         | 16384           | 32     | 512      | 181.0 | 193.3  | 195.464  | 268.4       | .6        | 95.9        | 285.3 (2.2)          | 46.5             | 262.055           | 463.805           | 268.112     |
| 128k/3:8k/97  | 2875         | 16384           | 256    | 4096     | 100.9 | 149.3  | 106.3235 | 3855.3      | .5        | 54.2        | 3024.6 (23.6)        | 50.5             | 2880.53           | 3855.6            | 2909.78     |
