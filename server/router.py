def ip_dst(pkt):
    return ".".join(map(str, pkt[16:20]))

def ip_src(pkt):
    return ".".join(map(str, pkt[12:16]))
