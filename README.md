# timewarpgw
Network lab to test the premise of Anycast GW without EVPN

![topology](https://raw.githubusercontent.com/topranks/timewarpgw/main/timewarp.png)


## Background

[Daniel Dib](https://x.com/danieldibswe) recently asked a very interesting question on Twitter:

[<img src="https://raw.githubusercontent.com/topranks/timewarpgw/main/twitterq.png">](https://x.com/danieldibswe/status/1800244577150161345)

He subsequently followed up with a very well written [blog piece](https://lostintransit.se/2024/06/25/why-didnt-we-have-anycast-gateways-before-vxlan/) on the matter.  However it was clear to me that Daniel was thinking of the question in a different way than I was.  His approach was to ask "why we didn't do anycast gateways given how we set up networks in the past", whereas I was thinking of it more in terms of "do we need EVPN to have anycast gw's, what about EVPN enables anycast gw?".

## Anycast GWs

Let's define what we mean by Anycast GW here.  To my mind it means a "vlan" or "irb" interface configured on every participating switch in a vlan, all of which use the **same IP** and the **same MAC address**.

To me the advantage of having such a thing is being able to make every top-of-rack or access switch act as gateway for connected hosts.  Daniel in his blog describes in a scenario in which an Anycast GW is of no benefit - spanning tree means traffic will always forward via one distribution switch, so it as VRRP master is fine.  But I wanted more to assess what would prevent us using Anycast GW in a scenario where it would bring some benefits, i.e. with a routed access layer.

### Benefits

The key benefit of having routing done on the first network device hosts are connected to is to have an optimal outbound path for packets a host on a Vlan sends to external IP networks.  The path traffic takes within a vlan is not affected by the use of Anycast GW, either with old-style vlan trunking, EVPN or anything else.  But for traffic going externally it is a benefit if the first switch processing the packet can route it, rather than briding it to another switch at layer-2 which then makes does the layer-3 lookup.

### Setup

So what would happen if we naively tried to make Anycast GWs in a traditional vlan spanning multiple switches?  Consider Vlan100 that I set up for the experiment, let's create an IP interface on every switch with this config:
```
interface Vlan100
 description VLAN100 ANYCAST GW
 mac-address 0200.5e77.7777
 ip address 198.51.100.1 255.255.255.0 secondary
 ip address 198.51.100.X 255.255.255.0
```

The idea here is that every switch that is configued for the vlan has an IP int on it, and we configure the same "secondary" IP on every one.  We also configure the same MAC address on each.  This ensures any ARP response for the 198.51.100.1 gateway from any switch will always have the correct MAC, regardless of what switch sends it.  So if a device moves from one switch to another (VM move or WiFi client for instance) they can continue sending external traffic to the same GW MAC.

### So what won't work?

Outbound traffic should work fine, with whatever switch a user is connected to dealing with frames for the GW MAC and routing them to their destination.

But what happens with inbound traffic?  Assume we are announcing the /24 IPv4 range belonging to this subnet to external routers from one or more switches participating in the Vlan.  How does a switch, receiving a packet for a host on the subnet, know what port it's on?  Without EVPN or any other fanciness this will be down to ARP.  If the packet from outside arrives on the switch the destination host is directly connected to this probably works ok.  The top-of-rack can send an ARP from the shared MAC address and will process the reply from the host, building the IP<->MAC binding and then use the L2 forwarding table to determine what port the MAC is on.  Things should work.

But what happens if the packet from outside routes to a switch the destination is not connected to?  That switch will try to ARP for the destination IP as before, but what happens?


[<img src="https://raw.githubusercontent.com/topranks/timewarpgw/main/tweet_problem.png">](https://x.com/toprankinrez/status/1800429524833984726)

**My theory was that the ARP would flood in the vlan as expected, and reach the host, but the response would not make it back to the switch that made the request**.  Instead the switch that the host is connected to would see the ARP response, with a destination MAC that it has locally configured on 'Vlan100', and try to process it itself.  The fact that all the devices are sharing a MAC on that interface, and thus have to use that MAC to source ARP requests, is going to prevent ARP responses getting back to any device other than the directly-connected one.


## Lab test

So I decided to test this out to see what would happen, and if there were any tricks of config knobs we could use to instead make it work.

### Lab setup

My go-to for all labs these days is [container lab](https://containerlab.dev/), which is amazing, but alas the main virtual-device I wanted to use for this one was Cisco [IOSvL2](https://docs.gns3.com/docs/using-gns3/beginners/switching-and-gns3/#iosvl2), which is a virtual Cisco switch, not unlike the Catalyst series of old, which comes with Cisco's [VIRL](https://learningnetwork.cisco.com/s/virl).  It just felt to me the right platform and device to be using to test this "could we do this back in the day" hypothesis.

There are no [vrnetlab](https://github.com/vrnetlab/vrnetlab) images to get IOSvL2 up and running quickly in containerlab, and not wanting to spend too much time on things I went back to the old reliable, [GNS3](https://www.gns3.com/).  This allowed me to quickly get a network of 5 switches built, connected as shown in the diagram at the top of the page.  I configured all the links between switches as layer-2 "trunks", but I set up a separate, dedicated vlan for each link on which I enabled OSPF.  So I sort of got an OSPF topology as if I had direct routed links everywhere, but using the vlan ints so I could also trunk other vlans.

I added several linux containers to the mix.  1 connected to each of the access switches, named 'server 1', 'server 2', and 'server 3'.  These were connected on a normal access port in Vlan100.  I trunked this vlan between all the switches also.  Every switch had the Vlan100 interface configured as shown in the last section, with the same MAC manually applied and the same 'secondary' IP.

### Checks

First let's make sure S1 can ping it's gateway:
```
root@S1:~# ip -br -4 addr show dev eth0
eth0             UNKNOWN        198.51.100.11/24 
```
```
root@S1:~# ip -4 route show 
default via 198.51.100.1 dev eth0 
198.51.100.0/24 dev eth0 proto kernel scope link src 198.51.100.11
```
```
root@S1:~# ping 198.51.100.1
PING 198.51.100.1 (198.51.100.1) 56(84) bytes of data.
64 bytes from 198.51.100.1: icmp_seq=1 ttl=255 time=1.01 ms
64 bytes from 198.51.100.1: icmp_seq=2 ttl=255 time=1.01 ms
```
```
root@S1:~# ip -4 neigh show dev eth0
198.51.100.1 lladdr 02:00:5e:77:77:77 REACHABLE
```

Ok all seems good there.  But what does a trace out to USER1 look like, which has IP address 192.0.2.1.

Firstly let's check this is ok from ASW1 where S1 is connected to.  Routing looks ok, it's learnt in OSPF (being redistributed from BGP by the DSWs):
```
ASW1#show ip route 192.0.2.1 
Routing entry for 192.0.2.0/30
  Known via "ospf 1", distance 110, metric 51
  Tag 65001, type extern 1
  Last update from 203.0.113.9 on Vlan201, 00:02:55 ago
  Routing Descriptor Blocks:
  * 203.0.113.9, from 203.0.113.25, 00:02:55 ago, via Vlan201
      Route metric is 51, traffic share count is 1
      Route tag 65001
```

(NOTE - I should have either just used OSPF or BGP for the routing, I tried to do what I thought would be quickest and ended up having to do more complex BGP<->OSPF redistribution that I'd like, but not relevant to the overall question).

Anyway ASW1 can trace just fine to this IP (note it is not using either of its IPs on Vlan100 to source this).
```
ASW1#traceroute 192.0.2.1 
Type escape sequence to abort.
Tracing the route to 192.0.2.1
VRF info: (vrf in name/id, vrf out name/id)
  1 203.0.113.9 1 msec 1 msec 2 msec
  2 203.0.113.1 1 msec 2 msec 1 msec
  3 192.0.2.1 2 msec 1 msec 3 msec
```

What happens if we ping from S1?
```
root@S1:~# ping -c 3 192.0.2.1
PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.

--- 192.0.2.1 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2032ms
```

Failed much as we expected, but was my theory right?  Looking on USER1 we can see the requests getting there, and replies are sent back:
```
root@USER1:~# tcpdump -i eth0 icmp 
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
12:29:03.946079 IP 198.51.100.11 > 192.0.2.1: ICMP echo request, id 8, seq 1, length 64
12:29:03.946099 IP 192.0.2.1 > 198.51.100.11: ICMP echo reply, id 8, seq 1, length 64
```

So the theory that outbound traffic won't be affect seems to bear out.  What on the return path is broken?  On R1 we see the traffic is being sent back to DSW1:
```
root@R1:/etc/bird# tcpdump -i eth0 -l -p icmp
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
12:30:10.463859 IP 198.51.100.11 > 192.0.2.1: ICMP echo request, id 9, seq 1, length 64
12:30:10.463978 IP 192.0.2.1 > 198.51.100.11: ICMP echo reply, id 9, seq 1, length 64
```

But what happens on DSW1?  As expected it is trying to ARP for the S1s IP, 198.51.100.11, but this is failing:

```
DSW1#show ip arp Vlan100
Protocol  Address          Age (min)  Hardware Addr   Type   Interface
Internet  198.51.100.5            -   0200.5e77.7777  ARPA   Vlan100
Internet  198.51.100.1            -   0200.5e77.7777  ARPA   Vlan100
Internet  198.51.100.2            0   Incomplete      ARPA   
Internet  198.51.100.11           0   Incomplete      ARPA   
```
A debug shows this clearer:
```
*Jul  6 12:39:59.662: IP ARP: creating incomplete entry for IP address: 198.51.100.11 interface Vlan100
*Jul  6 12:39:59.662: IP ARP: sent req src 198.51.100.5 0200.5e77.7777,
                 dst 198.51.100.11 0000.0000.0000 Vlan100
*Jul  6 12:40:01.689: IP ARP: sent req src 198.51.100.5 0200.5e77.7777,
                 dst 198.51.100.11 0000.0000.0000 Vlan100
```

However my theory wasn't 100% correct.  On S1 we don't seem to receive these ARPs:
```
root@S1:~# tcpdump -i eth0 -l -p -nn arp 
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
^C
0 packets captured
```

Firing up Wireshark from GNS3 the ARPs are visible on all 3 layer-2 trunks from DSW1 to the ASWs:

![arp_attempt](https://raw.githubusercontent.com/topranks/timewarpgw/main/arp_attempt.png)

But clearly ASW1 is not forwarding this broadcast out the access port to S1.  We can only assume that ASW1 does not like the source MAC on these frames being the same as it has on it's local Vlan100 interface, and is dropping them.

So I was slightly wrong about what would happen - at least with this virtual Cisco Catalyst switch - but in general the theory was correct.  **Having the same MAC configured on the Vlan interface across all switches prevents them from completing the ARP process for any hosts that aren't directly connected.**

## EVPN

How does EVPN solve this?  Well it's quite simple, in EVPN we have the EVPN/BGP control plane which distributes MAC/IP bindings in type-2 routes, so a remote switch does not have to send ARP requests to know the MAC for an IP connected anywhere on the fabric.  The control plane solves the issue for us.

## Could we make it work?

Are there any other tricks we could use to make it work?  Perhaps.

### Ditch mobility - stop using a shared MAC

Could we abandon using a shared MAC address on every switch?  If each had a unique MAC on the Vlan100 interface they should be able to ARP for hosts on the vlan right?

The major issue with this is that when a server ARPs for its gateway the broadcast will hit all switches as expected.  And they will all reply as they have the same IP configured.  If we have a shared MAC the multiple/duplicate ARP responses don't matter, they all respond with the same MAC for the GW IP so it doesn't matter which response is received first.  But if they all respond with different MACs then the host will randomly insert one or other in its ARP table.  And then we may not have the first-hop switch routing traffic again, defeating the purpose.

It might be possible to do this if we could put access-lists on the trunk ports between switches (but not access ports facing servers), _blocking ARP responses for the shared GW IP_.  Unfortuantely IOSvL2 doesn't seem to provide the ability to filter on this specifically so I couldn't try it.

This approach would also cause issues with VM mobility or wireless clients etc., as a host that moved its connection point to the network from one switch to another would have the wrong MAC still in its ARP cache for its gateway.  Traffic would still probably flow, but things would be sub-optimal until the client ARP entry expired and it retried the process, replacing the old switches MAC with the new one in its ARP table.

### Enter HSRP

Given the root of the problem is the requirement to ARP for hosts on the Vlan from any switch, while at the same time configuring every switch with the same IP and MAC, can we think of any other way to do it?

HSRP, when set up, uses two MAC addresses on a given interface.  It uses a unique MAC for packets sent by its unique IP, and a shared MAC (based on group ID) for packets sent from the shared VIP IP.  So it gives us what we need in terms of having two MAC/IP combinations, one unique it can use to source ARPs from, and another shared which act as gateway for connected hosts.

The issue of course is HSRP is not an Anycast gateway.  All devices will send HELLOs and a single active device will become active, and the rest all standby.  But what if we deliberatley mess with HSRP and block its control traffic?  Let's reconfigure all the Vlan100 interfaces like this:
```
ip access-list extended DROP_HSRP
 deny ip any host 224.0.0.102
 permit ip any any
!
interface Vlan100
 description VLAN100 ANYCAST GW
 ip address 198.51.100.x 255.255.255.0
 ip access-group DROP_HSRP in
 standby version 2
 standby 100 ip 198.51.100.1
```

Now if we look on any given switch it will be active, for instance DSW1:
```
DSW1#show standby 
Vlan100 - Group 100 (version 2)
  State is Active
    4 state changes, last state change 00:03:00
  Virtual IP address is 198.51.100.1
  Active virtual MAC address is 0000.0c9f.f064 (MAC In Use)
```

Or ASW1:
```
ASW1#show standby 
Vlan100 - Group 100 (version 2)
  State is Active
    2 state changes, last state change 00:03:01
  Virtual IP address is 198.51.100.1
  Active virtual MAC address is 0000.0c9f.f064 (MAC In Use)
```

So how do things look from our host now?  Success!  We can ping the USER1 IP:
```
root@S1:~# ping 192.0.2.1 
PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.
64 bytes from 192.0.2.1: icmp_seq=1 ttl=62 time=2.14 ms
64 bytes from 192.0.2.1: icmp_seq=2 ttl=62 time=1.80 ms
```

If we go to the USER1 container and trace out how do things look?  A traceroute shows the packets for any server going thorugh DSW1 and then hitting the server:

```
root@USER1:~# mtr -c 3 -r 198.51.100.11
Start: 2024-07-06T13:55:25+0000
HOST: USER1                       Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 192.0.2.2                  0.0%     3    0.2   0.2   0.2   0.2   0.0    # R1
  2.|-- 203.0.113.2                0.0%     3    1.0   1.0   0.9   1.0   0.1    # DSW1
  3.|-- 198.51.100.11              0.0%     3    2.7   2.1   1.8   2.7   0.5    # S1
```

```
root@USER1:~# mtr -c 3 -r 198.51.100.12
Start: 2024-07-06T13:55:37+0000
HOST: USER1                       Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 192.0.2.2                  0.0%     3    0.1   0.1   0.1   0.2   0.0   # R1
  2.|-- 203.0.113.2                0.0%     3    1.1   1.0   1.0   1.1   0.1   # DSW1
  3.|-- 198.51.100.12              0.0%     3    2.2   2.0   1.4   2.3   0.4   # S2
```

We don't see the ASW in the path as the packet is bridged within the vlan by DSW1.  But the forwarding path should be optimal.  The key thing is DSW1 can now ARP for the server IPs, using its unique (rather than shared HSRP) MAC on the Vlan:
```
interface Vlan100
 description VLAN100 ANYCAST GW
 ip address 198.51.100.5 255.255.255.0
 ip access-group DROP_HSRP in
 standby version 2
 standby 100 ip 198.51.100.1
```
Ping works from here too:
```
DSW1#ping 198.51.100.11         
Type escape sequence to abort.
Sending 5, 100-byte ICMP Echos to 198.51.100.11, timeout is 2 seconds:
!!!!!
Success rate is 100 percent (5/5), round-trip min/avg/max = 1/1/2 ms
```

If we debug ARP we can see the switch using it's unique IP/MAC to make the ARP request, and the response comes back:
```
*Jul  6 14:01:51.647: IP ARP: creating incomplete entry for IP address: 198.51.100.11 interface Vlan100
*Jul  6 14:01:51.647: IP ARP: sent req src 198.51.100.5 0c3c.054b.8064,
                 dst 198.51.100.11 0000.0000.0000 Vlan100
*Jul  6 14:01:51.649:  ARP rep is dequeued src 198.51.100.11/ce18.e085.6321, dst 198.51.100.5/0c3c.054b.8064 on Vlan100
*Jul  6 14:01:51.649: IP ARP: arp_process_request: 198.51.100.11, hw: ce18.e085.6321; rc: 3
*Jul  6 14:01:51.649: IP ARP: rcvd rep src 198.51.100.11 ce18.e085.6321, dst 198.51.100.5 0c3c.054b.8064 Vlan100
```

When the server ARPs for the GW IP, 198.51.100.1, the broadcast hits all the switches in the Vlan, and they all respond:
```
DSW1:

*Jul  6 14:05:37.460:  ARP req is dequeued src 198.51.100.11/ce18.e085.6321, dst 198.51.100.1/0000.0000.0000 on Vlan100
*Jul  6 14:05:37.460: IP ARP: arp_process_request: 198.51.100.11, hw: ce18.e085.6321; rc: 3
*Jul  6 14:05:37.461: IP ARP: rcvd req src 198.51.100.11 ce18.e085.6321, dst 198.51.100.1 0000.0000.0000 Vlan100
*Jul  6 14:05:37.461: IP ARP: sent rep src 198.51.100.1 0000.0c9f.f064,
                 dst 198.51.100.11 ce18.e085.6321 Vlan100

ASW1:

*Jul  6 14:05:37.553:  ARP req is dequeued src 198.51.100.11/ce18.e085.6321, dst 198.51.100.1/0000.0000.0000 on Vlan100
*Jul  6 14:05:37.553: IP ARP: arp_process_request: 198.51.100.11, hw: ce18.e085.6321; rc: 3
*Jul  6 14:05:37.553: IP ARP: rcvd req src 198.51.100.11 ce18.e085.6321, dst 198.51.100.1 0000.0000.0000 Vlan100
*Jul  6 14:05:37.553: IP ARP: sent rep src 198.51.100.1 0000.0c9f.f064,
                 dst 198.51.100.11 ce18.e085.6321 Vlan100

```

But ultimately this doesn't matter, the MAC they respond with is the same in all cases, so S1 inserts the correct entry in its ARP table.  Frames it sends to that MAC will always be processed by its connected top-of-rack, so routing works.

```
root@S1:~# ip neigh show 
198.51.100.1 dev eth0 lladdr 00:00:0c:9f:f0:64 REACHABLE
```

## Conclusion

So can we do an Anycast GW without EVPN?  I guess the answer is "kinda".  With bog-standard Ethernet and ARP we have a problem as we can't have a shared MAC address across all switches for the gateway, and still allow ARP to work everywhere.  If we add HSRP to the mix, and mess with it so that all the switches think they are active, we can pretty much get it to work.  This shouldn't be a surprise as Cisco's alternative to HSRP, GLBP, allowed for this for many years.  As do many protocols for MC-LAG such as VPC.

Daniel's point still stands.  In the typical L2 setup people used to do there is limited point trying this.  But if you were so inclined you could have all-active routing at the first hop, on a Vlan that is stretched across multiple devices.  If inbound routing sends traffic to a switch the destination isn't on then normal ARP + L2 bridging will get it from there to the destination just fine.
