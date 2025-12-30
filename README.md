# R8600-RC28-Controller
Software to use the ICOM RC-28 remote encoder with the R8600 radio via CI-V.  

Uses the Processing IDE and programming language, which is essentally Java.

This package needs the Hid4Java.jar and Jna.jar packages to work.  These are freely
available on-line and not included here as they are updated regulary on-line.

So as to be user configurable the controller software has a JSON file for config data such
as COMM port number and another JSON file for four pre-determined frequencies the RC-28 
can send to the radio.

The main Knob on the RC-28 works as you would expect, frequency control using the current
Controller step value. The TX button in conjuction with the main knob cycles through the
Controller frequency Step table or the Rx Mode tables.  The F1 and F2 buttons send one of
the four pre-determined frequencies to the radio dependent upon a short or long press of
these buttons.  Not managed to get the two LED's on the RC-28 to work yet!   

The current Controller Frequency Setp valus and that of the Radios Step value (TS) are
diplayed in the user interface.  The Controller will display the frequencys sent out on the
CI-V buss using the CI-V broadcast protocal.  

There are some keyboard commands but these do not seem to work very well in the current
version!  

Processing allows the software to be compiled and exported as a Windows .exe file and this is
included in a suitable named folder.

The folder structure shown here must be used for the sketch to compile.  
