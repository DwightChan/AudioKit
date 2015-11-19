//
//  AKMidiEvent.swift
//  AudioKit
//
//  Created by Jeff Cooper on 11/10/15.
//  Copyright © 2015 AudioKit. All rights reserved.
//

import Foundation
import CoreMIDI

/*
You add observers like this:
defaultCenter.addObserverForName(AKMidiStatus.NoteOn.name(), object: nil, queue: mainQueue, usingBlock: YourNotifFunction)

YourNotifFunction takes an NSNotifcation as an argument, 
and then all the good stuff is contained in the userInfo part of the notification

func myNotifFunction(notif:NSNotification) {
    print(notif.userInfo)
}
*/

/// A container for teh values that define a MIDI event
public struct AKMidiEvent {
    /// Internal data (Why the _?)
    var _data = [UInt8](count: 3, repeatedValue: 0)
    /// The length in bytes for this MIDI message (1 to 3 bytes)
    var length: UInt8?
    
    /// Status
    var status: AKMidiStatus {
        let status = _data[0] >> 4
        return AKMidiStatus(rawValue: Int(status))!
    }
    
    /// System Command
    var command: AKMidiSystemCommand {
        let status = (_data[0] >> 4)
        if(status < 15) {
            return .None
        }
        return AKMidiSystemCommand(rawValue:_data[0])!
    }
    
    /// MIDI Channel
    var channel: UInt8 {
        let status = (_data[0] >> 4)
        if (status < 15) {
            return (_data[0] & 0xF) + 1;
        }
        return 0
    }
    private var data1: UInt8 {
        return _data[1]
    }
    private var data2: UInt8 {
        return _data[2]
    }
    private var data: UInt16 {
        let x = UInt16(_data[1])
        let y = UInt16(_data[2] << 7)
        return y + x
    }
    
    private var bytes: NSData {
        return NSData(bytes: [_data[0], _data[1], _data[2]] as [UInt8], length: 3)
    }
    
    /// Initialize the MIDI Event from a MIDI Packet
    init(packet: MIDIPacket) {
        if (packet.data.0 < 0xF0) {
            let status = AKMidiStatus(rawValue: Int(packet.data.0) >> 4)
            let channel = UInt8(packet.data.0 & 0xF)+1
            fillWithStatus(status!, channel: channel, d1: packet.data.1, d2: packet.data.2)
        } else {
            fillWithCommand(AKMidiSystemCommand(rawValue: packet.data.0)!, d1: packet.data.1, d2: packet.data.2)
        }
    }
    
    /// Initialize the MIDI Event from a status message
    init(status: AKMidiStatus, channel: UInt8, d1: UInt8, d2: UInt8) {
        fillWithStatus(status, channel: channel, d1: d1, d2: d2)
    }
    private mutating func fillWithStatus(status: AKMidiStatus, channel: UInt8, d1: UInt8, d2: UInt8) {
        _data[0] = UInt8(status.rawValue << 4) | UInt8((channel-1) & 0xf);
        _data[1] = d1 & 0x7F;
        _data[2] = d2 & 0x7F;
        
        switch status {
        case .ControllerChange:
            if (d1 < AKMidiControl.DataEntryPlus.rawValue
                || d1 == AKMidiControl.LocalControlOnOff.rawValue) {
                    length = 3
            }
            else {
                length = 2
            }
        case .ChannelAftertouch: break
        case .ProgramChange:
            length = 2
        default:
            length = 3
        }
    }

    /// Initialize the MIDI Event from a system command message
    init(command: AKMidiSystemCommand, d1: UInt8, d2: UInt8) {
        fillWithCommand(command, d1: d1, d2: d2)
    }
    private mutating func fillWithCommand(command: AKMidiSystemCommand, d1: UInt8, d2: UInt8) {
        _data[0] = command.rawValue
        switch command {
        case .Sysex: break
        case .SongPosition:
            _data[1] = d1 & 0x7F;
            _data[2] = d2 & 0x7F;
            length = 3;
        case .SongSelect:
            _data[1] = d1 & 0x7F;
            length = 2;
        default:
            length = 1
        }
    }
    
    /// Broadcast a notification center message
    func postNotification() -> Bool {
        var ret = NSDictionary()
        let d1 = NSInteger(data1)
        let d2 = NSInteger(data2)
        let c  = NSInteger(channel)
        
        switch status {
            
        case .NoteOn, .NoteOff:
            ret = ["note":d1, "velocity":d2, "channel":c]
            
        case .PolyphonicAftertouch:
            ret = ["note":d1, "pressure":d2, "channel":c]
            
        case .ControllerChange:
            ret = ["control":d1, "value":d2, "channel":c]

        case .ChannelAftertouch:
            ret = ["pressure":d1, "channel":c]
            
        case .ProgramChange:
            ret = ["program":d1, "channel":c]
            
        case .PitchWheel:
            ret = ["pitchWheel":NSInteger(data), "channel":c]

        case .SystemCommand:
            switch (self.command) {
                case .Clock:
                    print("MIDI Clock")
                case .Sysex:
                    print("SysEx Command")
                case .SysexEnd:
                    print("SysEx EOX")
                case .SysReset:
                    print("MIDI System Reset")
                default:
                    print("Some other MIDI Status System Command")
            }

        }
        if (ret.count != 0) {
            NSNotificationCenter.defaultCenter().postNotificationName(status.name(),
                object: nil,
                userInfo: ret as [NSObject : AnyObject])
            return true;
        }
        return false;

    }//end postNotification
    
    // MARK: - Utility constructors for common MIDI events
    
    /// Create note on event
    static public func eventWithNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 ) -> AKMidiEvent {
        return AKMidiEvent(status:.NoteOn, channel: channel, d1: note, d2: velocity)
    }
    /// Create note off event
    static public func eventWithNoteOff(note: UInt8, velocity: UInt8, channel: UInt8) -> AKMidiEvent {
        return AKMidiEvent(status:.NoteOff, channel: channel, d1: note, d2: velocity)
    }
    /// Create program change event
    static public func eventWithProgramChange(program: UInt8, channel: UInt8) -> AKMidiEvent {
        return AKMidiEvent(status:.ProgramChange, channel: channel, d1: program, d2: 0)
    }
    /// Create controller event
    static public func eventWithController(control: UInt8, val: UInt8, channel: UInt8) -> AKMidiEvent {
        return AKMidiEvent(status:.ControllerChange, channel: channel, d1: control, d2: val)
    }

}