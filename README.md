# timewarpgw
Network lab to test the premise of Anycast GW without EVPN

![topology](https://raw.githubusercontent.com/topranks/timewarpgw/main/timewarp.png)


## Background

[Daniel Dib](https://x.com/danieldibswe) recently asked a very interesting question on Twitter:

![twitter question](https://raw.githubusercontent.com/topranks/timewarpgw/main/twitterq.png)

He subsequently followed up with a very well written [blog piece](https://lostintransit.se/2024/06/25/why-didnt-we-have-anycast-gateways-before-vxlan/) on the matter.  However it was clear to me that Daniel was thinking of the question in a different way than I was.  His approach was to ask "why we didn't do anycast gateways given how we set up networks in the past", whereas I was thinking of it more in terms of "do we need EVPN to have anycast gw's, what about EVPN enables anycast gw?".

## Anycast GWs

The concept of an anycast GW is fairly simple.  You have a "vlan" or "irb" interface configured on every participating switch in a vlan, all of which use the **same IP** and the **same MAC address**.  In this scneario you then have a situation where the switch a device is connected to is always acting as its IP gateway.  Unlike say with HSRP/VRRP where multiple swithces might be configured for the shared gateway, but only one is active at once.  In that scenario an outbound packet from a host might go from host -> switch1 -> switch2 and only then be routed to whatever external network is is going to.

There are of course some assumptions and some caveats in the scenario I'm explaining:

1) To my mind the concept of an anycast gateway is only relevant with a routed access layer
2) It seems pointless if there are L2 switches in the middle
4) I've no idea why Juniper have documentation on a "centralled routed bridging overlay" who wants that?
5) Yes I am opinionated on these things but I'm only playing
6) GLBP, a Cisco-proprietary alternative to HSRP and VRRP, can do the trick of having the connected switch always acting as IP gateway
7) Cisco VPC, and probably other solutions for MC-LAG, also manage to do the trick of every switch acting as IP gateway

To me an anycast gw is something you have when you are aiming for a fully-routed design with L3 at the access layer, _but for one reason or other you need some vlan stretching across switches_.  The valid reason for the latter could be VM mobility or device mobility in WiFi networks.  Both are probably solvable in other ways but they are at least credible reasons why you might need to trunk a vlan sometime.

## Can it be made work?

