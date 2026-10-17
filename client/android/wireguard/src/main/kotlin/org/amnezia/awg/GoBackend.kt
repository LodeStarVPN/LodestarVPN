package org.amnezia.awg

object GoBackend {
    external fun awgGetConfig(handle: Int): String?
    external fun awgGetSocketV4(handle: Int): Int
    external fun awgGetSocketV6(handle: Int): Int
    external fun awgTurnOff(handle: Int)
    external fun awgTurnOn(ifName: String, tunFd: Int, settings: String): Int
    external fun awgVersion(): String
    // what keeps the tunnel's direct sockets out of the VPN (SocketProtector); null: nothing
    external fun awgSetProtector(protector: Any?)
}

// The tunnel opens the connections to the networks the app sends past the VPN by itself (its
// sorter, tunnel/awg) and has each of their sockets kept out of the VPN by the service: the
// tunnel library calls protect(fd) on this object (jni.c finds the method by its name)
class SocketProtector(private val keep: (Int) -> Boolean) {
    fun protect(fd: Int): Boolean = keep(fd)
}
