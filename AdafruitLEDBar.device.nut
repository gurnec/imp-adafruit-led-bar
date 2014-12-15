// AdafruitLEDBar.device.nut -- Electric Imp driver for Adafruit's bargraph backpack
// Copyright (C) 2014 Christopher Gurnee
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// version 2 as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License version 2 for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
//
// If you find this program helpful, please consider a small
// donation to the developer at the following Bitcoin address:
//
//           17LGpN2z62zp7RS825jXwYtE7zZ19Mxxu8
//
//                      Thank You!

const BarBrightness_max = 15;

enum BarColor {
    off,
    red,
    orange,
    green
}

enum BarBlinkRate {
    not_blinking,
    two_hz,
    one_hz,
    half_hz
}

class AdafruitLEDBar
{
    my_i2c         = null;  // i2c object
    my_address     = null;  // i2c address (8-bit format)
    my_max_retries = null;  // before giving up on i2c.write()
    my_display_buf = null;  // uint16's of LED bits

    // i2c     - must already be configured (<= 400MHz SCL)
    // address - in the more common 7-bit format
    constructor(i2c, address = 0x70, max_retries = 10) {
        my_i2c         = i2c;
        my_address     = address << 1;
        my_max_retries = max_retries;
        my_display_buf = array(3, 0);
        _write("\x21");  // activate internal RC oscillator
    }

    // bar   - an int between 0 and 23 inclusive
    // color - BarColor.off, .red, .orange, or .green
    // (after calling set_bar() one or more times, call update_bars())
    function set_bar(bar, color) {

        // Calculate the position of the red LED
        // (the green LED is the red's cathode, anode+8)
        local anode, cathode;
                            // for the lower 12-LED bar:
        cathode = bar / 4;  //   matrix rows 0 - 2
        anode   = bar % 4;  //   matrix cols 0 - 3
        if (bar >= 12) {     // for the upper 12-LED bar:
            cathode -= 3;   //   matrix rows 0 - 2
            anode   += 4;   //   matrix cols 4 - 7
        }

        // Get the 16 anode bits
        local anodes = my_display_buf[cathode];

        // Update the red LED
        if (color == BarColor.red || color == BarColor.orange)
            anodes = anodes |   1 << anode;   // red bit on
        else
            anodes = anodes & ~(1 << anode);  // red bit off

        // Update the green LED
        anode += 8;
        if (color == BarColor.green || color == BarColor.orange)
            anodes = anodes |   1 << anode;   // green bit on
        else
            anodes = anodes & ~(1 << anode);  // green bit off

        // Store the 16 anode bits
        my_display_buf[cathode] = anodes;
    }

    // Update the LED bar; should be called after set_bar().
    // (not required after set_brightness() or set_blink_rate())
    function update_bars() {
        local data = blob(7);  // 1 address byte + 3 uint16's

        data.writen(0, 'b');  // set display address register to 0x00
        foreach (uint16 in my_display_buf)
            data.writen(uint16, 'w')
        _write(data.tostring());
    }

    // brightness - between 0 and BarBrightness_max (15) inclusive
    function set_brightness(brightness) {
        if (brightness < 0 || brightness > BarBrightness_max)
            throw "brightness out of range 0.." + BarBrightness_max;
        _write((0xE0 | brightness).tochar());
    }

    // rate - BarBlinkRate.not_blinking, .two_hz, .one_hz, or .half_hz
    function set_blink_rate(rate) {
        if (rate < 0 || rate > 3)
            throw "rate out of range 0..3";
        _write((0x81 | rate << 1).tochar());
    }

    // Resets bar to power-on defaults (all LEDs off, max brightness)
    function clear() {
        my_display_buf = array(3, 0);
        update_bars();
        set_brightness(BarBrightness_max);
        set_blink_rate(BarBlinkRate.not_blinking);
    }

    // Perform a write to the i2c bus, retrying on failures
    function _write(string) {
        local error;
        local tries = my_max_retries;
        while (tries--) {
            error = my_i2c.write(my_address, string);
            if (!error)
                break;
            // attempt a recovery by transitioning to standby mode
            my_i2c.write(my_address, "\x20");
            if (string != "\x21")
                my_i2c.write(my_address, "\x21");
        }
        if (error)
            throw "led bar i2c write error " + error;
    }
}
