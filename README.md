# timewarpgw
Network lab to test the premise of Anycast GW without EVPN

![topology](https://raw.githubusercontent.com/topranks/timewarpgw/main/timewarp.png)


## Background

[Daniel Dib](https://x.com/danieldibswe) recently asked a very interesting question on Twitter:

![twitter question](https://raw.githubusercontent.com/topranks/timewarpgw/main/twitterq.png)

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

**My theory was that the ARP would flood in the vlan as expected, and reach the host, but the response would not make it back to the switcht that made the request**.  Instead the switch that the host is connected to would see the ARP response, with a destination MAC that it has locally configured on 'Vlan100', and try to process it itself.  The fact that all the devices are sharing a MAC on that interface, and thus have to use that MAC to source ARP requests, is going to prevent ARP responses getting back to any device other than the directly-connected one.


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
root@S1:~# ip -4 neigh show dev eth0
198.51.100.1 lladdr 02:00:5e:77:77:77 REACHABLE
```

Ok all seems good there.  But what does a trace out to USER1 look like?

