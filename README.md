###################################################
## ioClarityWX v2
##
## This repo contains the following:
##   * Code for a JeeLink device which will intercept and decode
##     WX data from some models of LaCrosse weather stations into
##     a string of text via serial
##
##   * A Perl script that will read the stream of text from the 
##     JeeLink device collecting various WX data. At 11 minute 
##     intervals this script constructs a APRS WX string based
##     off the latest WX data, places it inside a AX.25 frame,
##     and then inside a KISS frame to be sent to a TCP/IP TNC.
##     Direwolf works great for this.
##
##   * A systemd service file, used for making the above perl
##     script into a system service. 
##
####################################################

Details of this project can be found on http://ioclarity.ca

At some point I will pad these instructions out, but for now these will do

Installation:
1) Procure a JeeLink: https://www.digitalsmarties.net/products/jeelink
     * This is essentially an Arduino with a radio board on it.

2) Install the Arduino code supplied in this repositiory onto the JeeLink
     * Do this with whatever Arduino code loading method you want to do.
     * Once done, you can test to make sure it works.  Simply open
       a terminal to the USB interface the JeeLink is plugged and wait.
       Assuming there is a wind or temp/humid sensor nearbuy, as it 
       beacons you should see a string of text.

3) Insall and configure direwolf or another TCP KISS TNC software. If
   you decide to use a serial interface to a TNC, you will need to modify
   the perl code suppled (next step) to use the serial interface
   instead of the TCP connection

4) Edit the Perl script and modify the variables required (things
   like your call, your GPS location, list of probs to monitor, 
   APRS route, etc)

5) Test the perl script.  it should beacon every 11 min

6) If all testing goes well, copy the systemd file to /etc/systemd/system
   Once copyed, enable the service to autostart:
	systemctl enable ioClarityWX
   and then start it manually:
	systemctl start ioClarityWX

- Enjoy
