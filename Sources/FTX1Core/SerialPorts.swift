import Foundation
import IOKit
import IOKit.serial

public enum SerialPorts {
    /// Every /dev/cu.* device, annotated with the USB interface and driver behind it.
    public static func enumerate() -> [SerialPort] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iter) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iter) }

        var ports: [SerialPort] = []
        while true {
            let svc = IOIteratorNext(iter)
            if svc == 0 { break }
            defer { IOObjectRelease(svc) }
            guard let path = prop(svc, kIOCalloutDeviceKey) as? String else { continue }
            ports.append(SerialPort(
                path: path,
                dialinPath: prop(svc, kIODialinDeviceKey) as? String,
                driver: driverName(svc),
                interfaceNumber: (search(svc, "bInterfaceNumber") as? NSNumber)?.intValue,
                interfaceName: search(svc, "kUSBString") as? String,
                usbProduct: search(svc, "USB Product Name") as? String,
                usbSerial: search(svc, "USB Serial Number") as? String,
                vendorID: (search(svc, "idVendor") as? NSNumber)?.intValue,
                productID: (search(svc, "idProduct") as? NSNumber)?.intValue
            ))
        }
        return ports.sorted { $0.path < $1.path }
    }

    private static func prop(_ e: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(e, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func search(_ e: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(e, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }

    /// Parent of IOSerialBSDClient is the driver; DriverKit drivers report their real class in IOUserClass.
    private static func driverName(_ svc: io_registry_entry_t) -> String {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(svc, kIOServicePlane, &parent) == KERN_SUCCESS else { return "?" }
        defer { IOObjectRelease(parent) }
        let raw: String
        if let user = prop(parent, "IOUserClass") as? String {
            raw = user
        } else {
            var buf = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &buf)
            raw = String(cString: buf)
        }
        switch raw {
        case "AppleUSBSLCOM": return "Apple"
        case "com_silabs_cp210x": return "Silicon Labs"
        default: return raw
        }
    }
}
