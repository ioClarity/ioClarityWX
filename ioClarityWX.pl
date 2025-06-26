#!/usr/bin/perl
#
# Perl script to decode the ioClarityWXReceiver JeeLink data and then
#   send out periodic APRS beacons with that info.  To be used with code supplied
#   running on the JeeLink.
# 
# version 2
#
#  History: v1 - 2020-00-00 - Original creation.  Cant remember date, was during COVID
#           v2 - 2025-06-23 - Modified to use KISS TNC directly rather than calling
#                             ax25 tools in OS (i.e. beacon).  Cleaner this way.
#
#  Author: Robert Gillis - VY1RG - robert@ioclarity.ca
#
#  Requires Device::SerialPort
use strict;
use POSIX;
use Device::SerialPort;
use IO::Socket::INET;

###   System variables ###
my $DEBUG = 0;                               # Change to one to have output on STDOUT for Debugging
my $WXFileDir = './wxdata/';                 # Directory to write WX CSV Data
my $jeeLinkBaudRate = 57600;                 # JeeLink Baud Rate
my $jeeLinkDataBits = 8;                     # JeeLink Data Bits
my $jeeLinkParity = 'none';                  # JeeLink Parity
my $jeeLinkHandshake = 'none';               # JeeLink Handshake
my $jeeLinkStopBits = 1;                     # JeeLink StopBits
my $jeeLinkDevice = "/dev/jeeLink";          # JeeLink Serial Port

## KISS TNC IP Variables - Currently only supports KISS TNC over IP ##
my $kissIpAddr = '127.0.0.1';		     # IP Address of Kiss TNC (direwolf likely)
my $kissIpAddrPort = 8001;                   # Port for IP Address

### These next four variables are used to determine what  temp probe to use for APRS beacons ###
###  (incase multiple are being picked up by JeeLink)                                        ###
my $aprsWXTempType = "LTVTH2";               # Type of temp Probe (currently only LTVTH2 is supported
my $aprsWXTempID = "012345";                 # Unique ID for temp probe to use
my $aprsWXWindType = "LTVW1";                # Type of wind Probe
my $aprsWXWindID = "d123a";                  # Unique ID for wind probe to use

### Variables to old the WX Data ###
my @windPack = ();                           # Used to hold Wind Data to calculate Gust
my $windPackGust = -1;                       # Used to hold the latest wind Gust Data
my %currentFrames;                           # Hash to hold the current weather data
                                             # Hash in the format of
                                             #   TYPE -> ID - > <<WX Data>>

### APRS specific variables ###
my $mycall = "MYCALL-1";                     # My station Callsign
my $aprsDest = "APIOWX";                     # APRS Destination   AP = APRS
                                             #                     IO = ioClarity
                                             #                     WX = ... well, WX
my @aprsPath = ("WIDE2-2");		     # Path to be used, Array of strings seperated by Commas
					     #   i.e. ("WIDE2-2")   or  ("WIDE2-2","RFONLY");
                                             #   adding RFONLY will keep the packets on RF only, not passing
                                             #   any iGates.  Great for testing
my $aprsLat = "1111.11N";                    # APRS LAT used
my $aprsLong = "22222.22W";                  # APRS LON used
my $aprsBeaconTime = 11;                     # How often, in minutes do we beacon the WX data
my $lastBeacon = 0;                          # Used to hold time of last time we APRS beaconed. Init to 0.


###############################################################################################
### First thing is first, try to open and configure the JeeLink serial port, if not abort ###
my $wxDataPort = Device::SerialPort->new($jeeLinkDevice) || die "Cannot open serial port";
$wxDataPort->baudrate($jeeLinkBaudRate); 
$wxDataPort->databits($jeeLinkDataBits);
$wxDataPort->parity($jeeLinkParity);
$wxDataPort->handshake($jeeLinkHandshake);
$wxDataPort->stopbits($jeeLinkStopBits);
$wxDataPort->stty_icanon(0);
$wxDataPort->stty_icrnl(0);
$wxDataPort->stty_echoe(0);
$wxDataPort->stty_echok(0);
$wxDataPort->stty_echoctl(0);
$wxDataPort->stty_echo(0);
$wxDataPort->stty_icanon(0);
$wxDataPort->stty_isig(0);
$wxDataPort->stty_opost(0);
$wxDataPort->stty_icrnl(0);
$wxDataPort->write_settings;

### Second thing is second, open and configure the KISS TNC connection (likely to direwolf) ###
my $kissTnc = IO::Socket::INET->new(
     PeerAddr => $kissIpAddr,
     PeerPort => $kissIpAddrPort,
     Proto    => 'tcp'
) or die "Cannot connect to kiss TNC: $!";


# Function to decode the WX data when recevied from the JeeLink device
# $_[0] is the string to decode
# 
sub decodeData
{
  if($DEBUG) { print "Decoding DataString @_[0] \n "; }
  
  #Parse out first two fields, which should be "OK" follwed by sensor type
  my ($start, $type, @rest) = split /\s+/, @_[0];
  if($start eq "OK") 
  {
     if($type eq "LTVTH2")
     {
        decodeLTVTH2(@rest);
     } elsif( $type eq "LTVW1")
     {
        decodeLTVW1(@rest);
     } elsif($DEBUG) { print "Not a known type -- ignoring --\n";  }

     # Add other sensor types here at a later timee
     #
  } elsif($DEBUG) { print "Not a valid string start -- ignoring --\n";  } 

}

# Function to parse the LaCrosse LTVTH2 sensor data as prepared by JeeLink
# $_[] contains the following data, in the following order
#
# LTVTH2 Data Format
#         ID S T T HH W N F F F 
#              1 2
#
#         ID = 6 char hex string repersenting ID          
#         S  = 1 digit Sequence ID
#         T1 = 1-3 digit Temp * 10 + 1000 MSB
#         T2 = 1-3 digit Temp * 10 + 1000 LSB
#         H  = 1-2 digit Humidity in percent
#         N  = 1 digit Weak Battery Flag
#         W  = 1 digit New Battery Flag
#         F  = 1 Future use flags
sub decodeLTVTH2
{
    if($DEBUG) { print "Decoding LTVTH2 String @_[0] \n "; }

    my $updateWXfile = 0;        # Used as a flag to update the CSV 
    my $type = "LTVTH2";
    my $id = $_[0];
    my $seq = $_[1];             # not doing anything with this yet
    my $h = $_[4];
    my $n = $_[5];
    my $w = $_[6];
    my $t = ((($_[2] * 256) + $_[3]) - 1000)/10;
    my $currentTime = time;

    # Handle the first time we decode a LTVTH2 frame from this ID
    if( ! exists $currentFrames{$type}{$id} )
    {
        $currentFrames{$type}{$id}{'timestamp'} = $currentTime; 
        $currentFrames{$type}{$id}{'lastupdate'} = $currentTime;
        $currentFrames{$type}{$id}{'temperature'} = $t;
        $currentFrames{$type}{$id}{'humidity'} = $h;
        $currentFrames{$type}{$id}{'weakBatteryFlag'} = $w;
        $currentFrames{$type}{$id}{'newBatteryFlag'} = $n;
        $updateWXfile = 1;
        if ($DEBUG) { print "First packet decoded from $type $id\n";}
    } else {
        # If this is not the first time we have heard this ID, and it has been over 
        # 15 minutes -OR- the temp, humidity or battery flags have changed update the 
        # hash and write the new data to the CSV
        if( (($currentTime - $currentFrames{$type}{$id}{'timestamp'}) > (15 * 60)) ||
            ($currentFrames{$type}{$id}{'temperature'} != $t) ||
            ($currentFrames{$type}{$id}{'humidity'} != $h) ||
            ($currentFrames{$type}{$id}{'weakBatteryFlag'} != $w) ||
            ($currentFrames{$type}{$id}{'newBatteryFlag'} != $n) 
           )
        {          
            if($DEBUG) { print "something changed since last write.. updating.\n"; }

            $currentFrames{$type}{$id}{'timestamp'} = $currentTime;   
            $currentFrames{$type}{$id}{'lastupdate'} = $currentTime;     
            $currentFrames{$type}{$id}{'temperature'} = $t;
            $currentFrames{$type}{$id}{'humidity'} = $h;
            $currentFrames{$type}{$id}{'weakBatteryFlag'} = $w;
            $currentFrames{$type}{$id}{'newBatteryFlag'} = $n;
            $updateWXfile = 1;                                          # Write to the CSV
        } else {
          # If nothing has changed since last packet, and it has been less than 15 minutes
          # update the lastupdate field (used for APRS Beacon)
            $currentFrames{$type}{$id}{'lastupdate'} = $currentTime;
            if($DEBUG) { print "nothing changed since last write.\n"; }
        }
    }

    # If we are to update the CSV, this code does it, in the following format:
    # DATE,TIME,TYPE,ID,TEMP,HUMIDITY
    # (not doing antyhing with the battery flags at the moment)
    if ( $updateWXfile )
    {
        if($DEBUG) { print "Writing to WX File\n"; }
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($currentFrames{$type}{$id}{'timestamp'});
        $year += 1900;
        $mon++;
        my $dateString=sprintf("%04d-%02d-%02d",$year,$mon,$mday);
        my $timeString=sprintf("%02d\:%02d\:%02d",$hour,$min,$sec);
        
        open(WXFILE, '>>', $WXFileDir."$dateString.csv");
        print WXFILE "$dateString,$timeString,$type,$id,$currentFrames{$type}{$id}{'temperature'},$currentFrames{$type}{$id}{'humidity'}%\n";
        close(WXFILE);
    }
}

sub avg {
    my $total;
    $total += $_ foreach @_;
    # sum divided by number of components.
    return $total / @_;
}

sub addWindData
{
    if($DEBUG) { print "Adding Wind Data  $_[0] \n "; }
    push( @windPack, $_[0] );
    if($windPackGust < $_[0])
    {
       $windPackGust = $_[0];
    }
    if($DEBUG) { print "Wind Pack @windPack \n "; print "Wind Gust: $windPackGust\n";}

}

sub getWindDataAvg
{
   if ( (scalar @windPack) > 0  )
   {
     return avg(@windPack);
   }
   else { return -1; }
}

sub getWindGust
{
    if ( (scalar @windPack) > 0 )
    {
       return $windPackGust;
    }
    else { return -1; }
}    

sub resetWindData
{
    @windPack = ();
    $windPackGust = -1;
}


# Function to parse the LaCrosse LTVW1 sensor data as prepared by JeeLink
# $_[] contains the following data, in the following order
#
# LTVW1 Data Format
#         ID S G G N W F F F F 
#              1 2
#
#         ID = 6 char hex string repersenting ID          
#         S  = 1 digit sequence ID
#         G1 = 1-3 digit Wind (Km/h) * 10 MSB
#         G2 = 1-3 digit Wind (Km/h) * 10 LSB
#         W  = 1 digit Weak Battery Flag
#         N  = 1 digit New Battery Flag
#         F  = 1 Future use flags
sub decodeLTVW1
{
    if($DEBUG) { print "Decoding LTVW1 String @_[0] \n "; }

    my $updateWXfile = 0;        # Used as a flag to update the CSV 
    my $type = "LTVW1";
    my $id = $_[0];
    my $seq = $_[1];             # not doing anything with this yet
    my $n = $_[4];
    my $w = $_[5];
    my $wind = ((($_[2] * 256) + $_[3]))/10;
    my $currentTime = time;

    addWindData( $wind );    # always add wind data for wind speed aprs average
    
    # Handle the first time we decode a LTVW1 frame from this ID
    if( ! exists $currentFrames{$type}{$id} )
    {
        $currentFrames{$type}{$id}{'timestamp'} = $currentTime; 
        $currentFrames{$type}{$id}{'lastupdate'} = $currentTime;
        $currentFrames{$type}{$id}{'windSpeed'} = $wind;
        $currentFrames{$type}{$id}{'weakBatteryFlag'} = $w;
        $currentFrames{$type}{$id}{'newBatteryFlag'} = $n;
        $updateWXfile = 1;
        if ($DEBUG) { print "First packet decoded from $type $id\n";}
    } else {
        # If this is not the first time we have heard this ID, and it has been over 
        # 15 minutes -OR- the windSpeed, or battery flags have changed update the 
        # hash and write the new data to the CSV
        if( (($currentTime - $currentFrames{$type}{$id}{'timestamp'}) > (15 * 60)) ||
            ($currentFrames{$type}{$id}{'windSpeed'} != $wind) ||
            ($currentFrames{$type}{$id}{'weakBatteryFlag'} != $w) ||
            ($currentFrames{$type}{$id}{'newBatteryFlag'} != $n) 
           )
        {          
            if($DEBUG) { print "something changed since last write.. updating.\n"; }

            $currentFrames{$type}{$id}{'timestamp'} = $currentTime;   
            $currentFrames{$type}{$id}{'lastupdate'} = $currentTime;     
            $currentFrames{$type}{$id}{'windSpeed'} = $wind;
            $currentFrames{$type}{$id}{'weakBatteryFlag'} = $w;
            $currentFrames{$type}{$id}{'newBatteryFlag'} = $n;
            $updateWXfile = 1;                                          # Write to the CSV
        } else {
          # If nothing has changed since last packet, and it has been less than 15 minutes
          # update the lastupdate field (used for APRS Beacon)
            $currentFrames{$type}{$id}{'lastupdate'} = $currentTime;
            if($DEBUG) { print "nothing changed since last write.\n"; }
        }
    }

    # If we are to update the CSV, this code does it, in the following format:
    # DATE,TIME,TYPE,ID,TEMP,HUMIDITY
    # (not doing antyhing with the battery flags at the moment)
    if ( $updateWXfile )
    {
        if($DEBUG) { print "Writing to WX File\n"; }
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($currentFrames{$type}{$id}{'timestamp'});
        $year += 1900;
        $mon++;
        my $dateString=sprintf("%04d-%02d-%02d",$year,$mon,$mday);
        my $timeString=sprintf("%02d\:%02d\:%02d",$hour,$min,$sec);
        
        open(WXFILE, '>>', $WXFileDir."$dateString.csv");
        print WXFILE "$dateString,$timeString,$type,$id,$currentFrames{$type}{$id}{'windSpeed'}\n";
        close(WXFILE);
    }
}


# Function to send an APRS Beacon with the current WX 
sub aprsBeacon
{
    # If this is the first beacon, or it has been over "aprsBeaconTime" minutes
    # beacon out the latest weather assuming we have weather data
    my $currentTime = time; 

    if ($DEBUG) { print "Checking if we need to beacon\n$currentTime\n$lastBeacon\n"; };
    # If a frame exists AND
    #    we have never beaconed -OR- it has been over the $aprsBeaconTime
    # then we beacon.
    if( exists $currentFrames{$aprsWXTempType}{$aprsWXTempID} and
       ( ( $lastBeacon == 0 ) or
         ( (time - $lastBeacon) >= ( 60*$aprsBeaconTime ) )) )
    {
      if ($DEBUG) { print "Frame exists, and we need to beacon\n"; };
       
       # Checks to see if we have recent data within the last 10 minutes, by checking the lastupdate 
       # set on the current WX Temp frame.  This prevents sending out data that has not been updated recently
       if ( ($currentTime - $currentFrames{$aprsWXTempType}{$aprsWXTempID}{'lastupdate'} ) <= (60*10) )
       {
         if($DEBUG) { print "***beaconing***\n"; } 
            
         # Okay, we are good to build the KISS Frame, and send it to the KISS TNC (i.e. beacon!)
         $kissTnc->send( buildKissFrame() );
        
         $lastBeacon = $currentTime;   # update the last time we beaconed to now
       }
       else { if($DEBUG) { print "not beaconing, too soon since last beacon\n"; } }
   }
}

#
#  Build the Kiss frame for the KISS TNC
#
sub buildKissFrame {

   # Get GMT Time
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($currentFrames{$aprsWXTempType}{$aprsWXTempID}{'lastupdate'});
   my $aprsDateTime = sprintf("%02d%02d%02d",$mday,$hour,$min);

   # Get temperature rounded to the nearest F degree, and humidity.
   my $realTempC = $currentFrames{$aprsWXTempType}{$aprsWXTempID}{'temperature'};
   my $realTempF = ($realTempC * (9/5) ) + 32;
   my $realHumidity = $currentFrames{$aprsWXTempType}{$aprsWXTempID}{'humidity'};
   my $roundedTempF = int($realTempF + $realTempF/abs($realTempF*2 || 1));

   # Encode the temperature (always 3 placeholders), and humidity (always 2 placeholders)
   my $encodedTemp = sprintf("%03d", $roundedTempF);
   my $encodedHumidity = sprintf("%02d", $realHumidity);

   # Get the windData, convert to MPH and encode it
   my $avgWindSpeedKPH = getWindDataAvg();
   my $windGustKPH = getWindGust();

   my $avgWindSpeedMPH = $avgWindSpeedKPH / 1.609;
   my $roundedWindSpeedMPH = int($avgWindSpeedMPH + $avgWindSpeedMPH/abs($avgWindSpeedMPH*2 || 1));

   my $windGustMPH = $windGustKPH / 1.609;
   my $roundedWindGustMPH = int($windGustMPH + $windGustMPH/abs($windGustMPH*2 || 1));

   my $encodedWindMPH = "...";
   my $encodedGustMPH = "...";

   if ( ($avgWindSpeedKPH > -1 ) && ($windGustKPH > -1) )
   {
       $encodedWindMPH = sprintf("%03d", $roundedWindSpeedMPH);
       $encodedGustMPH = sprintf("%03d", $roundedWindGustMPH);
       resetWindData();
   }

   # Okay, put the above together - its the payload
   my $payload = "\@${aprsDateTime}z${aprsLat}/${aprsLong}_.../${encodedWindMPH}g${encodedGustMPH}t${encodedTemp}h${encodedHumidity} ioClarity LaCr WX-v2";
   if ($DEBUG) { print "APRS Payload STring: $payload\n"; }

   # Below is nested subroutine which helps to encode AX.25 address
    sub ax25_addr {
        my ($call, $ssid, $last) = @_;
        my @addr = map { (ord($_) << 1) } split('', uc($call));
        push @addr, (0x40) x (6 - @addr);  # pad to 6 chars
        push @addr, (($ssid & 0x0F) << 1) | ($last ? 0x01 : 0x60);
        return @addr;
    }
  
   # ... and a nested subroutine which helps parse the callsignes and SSIDs
    sub parse_callsign_ssid {
       my ($input) = @_;
    
       # Match callsign and optional SSID
       if ($input =~ /^([A-Z0-9]+)(?:-(\d+))?$/i) {
           my $callsign = $1;
           my $ssid = defined $2 ? int($2) : 0;  # Default SSID to 0 if not present
           return ($callsign, $ssid);
       } else {
           die "Invalid callsign format: $input";
       }
    } 

    # Create the AX.25 header / Frame
    my @ax25Frame;
    push @ax25Frame, ax25_addr((parse_callsign_ssid($aprsDest)), 0);     # Destination
    push @ax25Frame, ax25_addr((parse_callsign_ssid($mycall)), 0);   # Source (last address)

   if($DEBUG) { print "ax25 header built with $aprsDest, $mycall"; }

    #Add the Path
    for my $i (0..$#aprsPath) {
       my $last = ($i == $#aprsPath);
       push @ax25Frame, ax25_addr((parse_callsign_ssid($aprsPath[$i])), $last);
       if ($DEBUG) { print ", $aprsPath[$i]"; }
    }

    #if no path, then set the source address as last addr in header
    if (@aprsPath == 0) {
        $ax25Frame[13] |= 0x01;  # Set LSB of source address's last byte
    }

    if($DEBUG) { print "\n"; };

    push @ax25Frame, 0x03;  		     # Control field: UI frame
    push @ax25Frame, 0xF0;                   # PID: no layer 3

    # Convert the payload string into a list of binary charcters, and add those to the frame away
    push @ax25Frame, map { ord($_) } split('', $payload);

    if($DEBUG) { print "AX.25 Frame: ", join(' ', map { sprintf("%02X", $_) } @ax25Frame), "\n"; }

    # Wrap in KISS frame
    my @kissFrame = (0xC0, 0x00, @ax25Frame, 0xC0);  # 0x00 = data frame
    if($DEBUG) { print "Kiss Frame: ", join(' ', map { sprintf("%02X", $_) } @kissFrame), "\n"; }

    # return the list of 'packed' binary frame that can be sent to the KISS TNC

    return pack('C*', @kissFrame);
}


############################## Main Program

#
# Main program loop
#
while (1) {

    # Get input from JeeLink
    my $input = $wxDataPort->input;

    # If received input from the JeeLink, try to decode it
    if ($input) {
        if($DEBUG) { print "Received input\n"; }
        decodeData($input);
        if($DEBUG) { print "Done Decoding\n";}
    }

    $wxDataPort->lookclear; # needed to prevent blocking

    # Sleep for 2 seconds before looking for input again
    sleep (2);

    # Determine if we need to APRS Beacon or not
    aprsBeacon();

}
