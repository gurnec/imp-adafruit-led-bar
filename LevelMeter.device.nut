// LevelMeter.device.nut -- level meter based on an LED bar graph
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

class LevelMeter
{
    my_led_bar      = null;  // AdafruitLEDBar object
    my_min          = null;  // min value of meter (int or float)
    my_max          = null;  // max value of meter (int or float)
    my_range        = null;  // half-open range of meter [min, max)
    my_bar_count    = null;  // total # of bars available (default: 24)
    my_noise        = null;  // see set_noise()
    my_cur_level    = null;  // the current meter level
    my_low_warn     = null;  // see...
    my_low_crit     = null;  // ...set_low_warnings()
    my_high_warn    = null;  // see...
    my_high_crit    = null;  // ...set_high_warnings()
    my_fillup_timer = null;  // timer handle; see _update_level()

    // led_bar   - AdafruitLEDBar object
    // min       - int or float min value  (defaults to imp's
    // max       - int or float max value   16-bit ADC range)
    // bar_count - # of LED bars available
    constructor(led_bar, min = 0, max = 65535, bar_count = 24) {
        my_led_bar   = led_bar;
        my_min       = min;
        my_max       = max;
        my_bar_count = bar_count.tointeger();
        _update_range(min, max);
        set_noise_default();
    }

    // min - min value of the meter (int or float)
    // (consider calling set_noise_default() after this)
    function set_min(min) {
        _update_range(min, my_max);
        my_min = min;
        _update_level();
    }

    // max - max value of the meter (int or float)
    // (consider calling set_noise_default() after this)
    function set_max(max) {
        _update_range(my_min, max);
        my_max = max;
        _update_level();
    }

    // calculate and set the half-open range based on min and max
    function _update_range(min, max) {
        local range = max - min;
        if (range <= 0)
            throw "LevelMeter min >= max";
        if (typeof(range) == "integer")
            range++;
        my_range = range;
    }

    // new_level - int or float typically between min and max inclusive
    // returns   - the "registered" difference (see set_noise())
    //             or null if this is the first call to set_cur_level()
    // Updates the level meter; if the level is rising
    // (is being filled), it becomes temporarily brighter.
    function set_cur_level(new_level) {
        local last_level = my_cur_level;
        local difference = last_level==null? null : new_level - last_level;
        if (difference != null && (difference<0? -difference:difference) < my_noise)
            return 0;

        my_cur_level = new_level;
        _update_level(last_level);
        return difference;
    }

    // noise - the amount by which the new_level must change in
    //         order to be registered by the level meter
    //         (defaulted to 1/2 of an LED bar in constructor())
    function set_noise(noise) {
        my_noise = noise;
    }

    // returns - the newly calculated noise threshold
    // Sets the noise to be 1/2 of an LED bar based on the min and max.
    // (iff min and max are ints, there's a small performance advantage
    //  when max - min + 1 % 48 == 0)
    function set_noise_default() {
        local double_bars = my_bar_count << 1;
        if (typeof(my_range) == "integer" && my_range % double_bars == 0)
            return my_noise = my_range / double_bars;

        return my_noise = my_range.tofloat() / double_bars;
    }

    // low_warn - a bar count (between 1 and 24 inclusive)
    // low_crit - same; typically less than low_warn
    // These thresholds change the color of bars below them. Also,
    // at the low_warn threshold, the level meter becomes bright.
    // At the low_crit threshold, the level meter also begins flashing.
    function set_low_warnings(low_warn = 6, low_crit = 3) {
        my_low_warn = low_warn;
        my_low_crit = low_crit;
        _update_level();
    }

    // high_warn - a bar count (between 1 and 24 inclusive)
    // high_crit - same; typically greater than high_warn
    // These thresholds only affect the level meter when it's rising.
    // At the high_warn threshold, the entire meter temp. turns orange.
    // At the high_crit threshold, the entire meter temp. turns red.
    function set_high_warnings(high_warn = 19, high_crit = 22) {
        my_high_warn = high_warn;
        my_high_crit = high_crit;
        _update_level();
    }

    function _update_level(last_level = null) {
        if (my_cur_level == null)
            return;

        // Step 1: determine the number of bars to light

        local bars = ((my_cur_level - my_min) * my_bar_count / my_range).tointeger() + 1;
        if (bars > my_bar_count)
            bars = my_bar_count;
        if (bars < 1)
            bars = 1;

        // Step 2: determine brightness, blink rate, and color override

        local one_color;  // the color override, if any

        // being filled: make bright and possibly override the color
        local is_rising = last_level != null && my_cur_level > last_level;
        if (is_rising || my_fillup_timer) {  // if rising now or recently
            if (!my_fillup_timer) {  // if not already bright
                my_led_bar.set_brightness(BarBrightness_max);
                my_led_bar.set_blink_rate(BarBlinkRate.not_blinking);
            }
            //
            if (is_rising) {  // (re)schedule the return-to-dim timer
                if (my_fillup_timer)
                    imp.cancelwakeup(my_fillup_timer);
                my_fillup_timer = imp.wakeup(15.0, _update_when_inactive.bindenv(this))
            }
            //
            if (my_high_crit != null && bars >= my_high_crit)
                one_color = BarColor.red;
            else if (my_high_warn != null && bars >= my_high_warn)
                one_color = BarColor.orange;

        // critically low: make bright and blink
        } else if (my_low_crit != null && bars <= my_low_crit) {
            my_led_bar.set_brightness(BarBrightness_max);
            my_led_bar.set_blink_rate(BarBlinkRate.two_hz);

        // low warning: just make bright
        } else if (my_low_warn != null && bars <= my_low_warn) {
            my_led_bar.set_brightness(BarBrightness_max);
            my_led_bar.set_blink_rate(BarBlinkRate.not_blinking);

        // all OK: make dim
        } else {
            my_led_bar.set_brightness(0);
            my_led_bar.set_blink_rate(BarBlinkRate.not_blinking);
        }

        // Step 3: set bar colors

        if (one_color) {
            for (local b = 0; b < bars; b++)
                my_led_bar.set_bar(b, one_color)

        // colorize according to the low thresholds
        } else {
            for (local b = 0; b < bars; b++) {
                if (my_low_crit != null && b < my_low_crit)
                    my_led_bar.set_bar(b, BarColor.red);
                else if (my_low_warn != null && b < my_low_warn)
                    my_led_bar.set_bar(b, BarColor.orange);
                else
                    my_led_bar.set_bar(b, BarColor.green);
            }
        }

        // clear the bars above the current level
        for (local b = bars; b < my_bar_count; b++)
            my_led_bar.set_bar(b, BarColor.off);

        my_led_bar.update_bars();
    }

    function _update_when_inactive() {
        my_fillup_timer = null;
        _update_level();
    }
}
