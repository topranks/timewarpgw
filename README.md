# timewarpgw
Network lab to test the premise of Anycast GW without EVPN

![topology](https://raw.githubusercontent.com/topranks/timewarpgw/main/timewarp.png)


## Background

[Daniel Dib](https://x.com/danieldibswe) recently asked a very interesting question on Twitter:

![twitter question](https://raw.githubusercontent.com/topranks/timewarpgw/main/twitterq.png)

He subsequently followed up with a very well written [blog piece](https://lostintransit.se/2024/06/25/why-didnt-we-have-anycast-gateways-before-vxlan/) on the matter.  However it was clear to me that Daniel was thinking of the question in a different way than I was.  His approach was to ask "why we didn't do anycast gateways given how we set up networks in the past", whereas I was thinking of it more in terms of "do we need EVPN to have anycast gw's, what about EVPN enables anycast gw?".

## Anycast GWs

The concept of an anycast GW is fairly simple.  You have a "vlan" or "irb" interface configured on every participating switch in a vlan, all of which use the **same IP** and the **same MAC address**.  Obviously this is somewhat heretical, we have duplicate IPs on the same ethernet segment, and indeed duplicate MACs!  Not something anyone anticipated doing when the idea of running IPv4 over Ethernet first came about.  Nevertheless, it's something we do now and it works well, at least with virtual Ethernet networks built with an EVPN control plane.

In the Anycast GW scneario the switch a device is connected to is always acting as its IP gateway.  Unlike say with HSRP/VRRP where multiple swithces might be configured for the shared gateway, but only one is active at once.  In that scenario an outbound packet from a host might go from host -> switch1 -> switch2 and only then be routed to whatever external network is is going to.

There are of course some assumptions and some caveats in the scenario I'm explaining:

1) To my mind the concept of an anycast gateway is only relevant with a routed access layer
2) It seems pointless if there are L2 switches in the middle
4) I've no idea why Juniper have documentation on a "centralled routed bridging overlay" who wants that?
5) Yes I am opinionated on these things but I'm only playing
6) GLBP, a Cisco-proprietary alternative to HSRP and VRRP, can do the trick of having the connected switch always acting as IP gateway
7) Cisco VPC, and probably other solutions for MC-LAG, also manage to do the trick of every switch acting as IP gateway

To me an anycast gw is something you have when you are aiming for a fully-routed design with L3 at the access layer, _but for one reason or other you need some vlan stretching across switches_.  The valid reason for the latter could be VM mobility or device mobility in WiFi networks.  Both are probably solvable in other ways but they are at least credible reasons why you might need to have the same vlan on separate switches.

## Can it be made work?

So we get down to the question, could this work without EVPN?  What is it about EVPN that enables it?

I had some ideas, but I wanted to test it out, and also see if maybe I could find any config knobs that would have made it possible with typical gear in the past.  My go-to for all labs these days is [container lab](https://containerlab.dev/), which is amazing, but alas the main virtual-device I wanted to use for this one was Cisco [IOSvL2](https://docs.gns3.com/docs/using-gns3/beginners/switching-and-gns3/#iosvl2), which is a virtual Cisco switch, not unlike the Catalyst series of old, which comes with Cisco's [VIRL](https://learningnetwork.cisco.com/s/virl).  It just felt to me the right platform and device to be using to test this "could we do this back in the day" hypothesis.

There are no [vrnetlab](https://github.com/vrnetlab/vrnetlab) images to get IOSvL2 up and running quickly in containerlab, and not wanting to spend too much time on things I went back to the old reliable, [GNS3](https://www.gns3.com/).  This allowed me to quickly get a network of 5 switches built, connected as shown in the diagram at the top of the page.  I configured all the links between switches as layer-2 "trunks", but I set up a separate, dedicated vlan for each link on which I enabled OSPF.  So I sort of got an OSPF topology as if I had direct routed links everywhere, but using the vlan ints so I could also trunk other vlans.

I added several linux containers to the mix.  1 connected to each of the access switches, named 'server 1', 'server 2', and 'server 3'.  These were connected on a normal access port in Vlan100.  I trunked this vlan between all the switches also.  
