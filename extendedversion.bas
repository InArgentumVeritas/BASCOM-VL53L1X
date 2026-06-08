$regfile = "m644pdef.dat"
$crystal = 16000000
$baud = 9600

' === LCD CONFIGURATION ===
Config Lcdpin = Pin , Db4 = Portc.4 , Db5 = Portc.5 , Db6 = Portc.6 , Db7 = Portc.7 , E = Portc.3 , Rs = Portc.2
Config Lcd = 16 * 2
Cursor Off
Deflcdchar 1 , 6 , 9 , 9 , 6 , 32 , 32 , 32 , 32  ' Degree symbol

' Configure SHUT pin for hardware reset
Config PinD.2 = Output  ' SHUT/Reset pin
Shut Alias PortD.2

' === 1-WIRE FOR DS18B20 ===
Config 1wire = Pind.4

' === SINGLE I2C BUS FOR BOTH VL53L1X AND PCF8563 ===
Config Sda = Portc.1
Config Scl = Portc.0
I2cinit
Twbr = 72  ' ~100kHz for stable I2C

' ===== VL53L1X REGISTER DEFINITIONS =====
Const VL53L1_I2C_ADDR = &H0001
Const VL53L1_HV_CONFIG = &H002E
Const VL53L1_POWER_FORCE = &H0083
Const VL53L1_FIRMWARE_EN = &H0085
Const VL53L1_INT_CLEAR = &H0086
Const VL53L1_MODE_START = &H0087
Const VL53L1_INT_STATUS = &H0088
Const VL53L1_RANGE_STATUS = &H0089
Const VL53L1_REPORT_STATUS = &H008A
Const VL53L1_DISTANCE_SD0 = &H0096
Const VL53L1_PEAK_SIGNAL_SD0 = &H008E
Const VL53L1_AMBIENT_SD0 = &H0090
Const VL53L1_SIGNAL_XTALK_SD0 = &H0098
Const VL53L1_FW_STATUS = &H00E5
Const VL53L1_MODEL_ID = &H010F
Const VL53L1_ROI_CENTRE = &H007F
Const VL53L1_ROI_SIZE = &H0080
Const VL53L1_INT_CONFIG = &H0046
Const VL53L1_INTERMEASURE = &H006C
Const VL53L1_VCSEL_A = &H0060
Const VL53L1_VCSEL_B = &H0063
Const VL53L1_TIMEOUT_A_HI = &H005E
Const VL53L1_TIMEOUT_A_LO = &H005F
Const VL53L1_TIMEOUT_B_HI = &H0061
Const VL53L1_TIMEOUT_B_LO = &H0062

' === VARIABLES FOR RTC TIME ===
Dim Time_set_flag As Bit
Time_set_flag = 0

Dim Set_year As Byte
Dim Set_month As Byte
Dim Set_day As Byte
Dim Set_weekday As Byte
Dim Set_hour As Byte
Dim Set_minute As Byte
Dim Set_second As Byte
Dim Rtc_seconds As Byte
Dim Rtc_minutes As Byte
Dim Rtc_hours As Byte
Dim Rtc_day As Byte
Dim Rtc_weekday As Byte
Dim Rtc_month As Byte
Dim Rtc_year As Byte

' For BCD conversion
Dim Tens As Byte
Dim Units As Byte

' === DAY NAMES (Polish) ===
Dim Weekday_names(7) As String * 4
Weekday_names(1) = " Nd"
Weekday_names(2) = "Pon"
Weekday_names(3) = " Wt"
Weekday_names(4) = " Sr"
Weekday_names(5) = "Czw"
Weekday_names(6) = " Pt"
Weekday_names(7) = " Sb"

' VL53L1X Variables
Dim Device_address_write As Byte
Dim Device_address_read As Byte
Dim Value As Word
Dim Data_byte As Byte
Dim Data_low As Byte
Dim Data_high As Byte
Dim Addr As Word
Dim Distance As Word
Dim I As Byte
Dim Loop_cnt As Word
Dim Signal_rate As Word
Dim Ambient_rate As Word
Dim Range_status As Byte
Dim Report_status As Byte
Dim Measurement_count As Word
Dim Sig_threshold As Word  ' For signal threshold calculation

' For timestamp display
Dim Dec_value As Byte

' Range mode tracking
Dim Current_range_mode As Byte  ' 1=SHORT, 2=MEDIUM, 3=LONG
Dim New_range_mode As Byte
Dim Range_mode_changed As Bit
Dim Wrong_mode_count As Byte  ' Hysteresis counter
Dim Hw_failure_count As Byte   ' Hardware failure counter
Dim Previous_mode As Byte      ' Track previous mode for display
Dim Low_signal_counter As Byte ' Count consecutive LOW signals
Dim High_power_active As Bit   ' Flag for high-power mode
Dim Manual_mode_active As Bit  ' Flag for manual mode lock
Manual_mode_active = 0         ' Start in auto mode

' === ROI Variables ===
Dim Roi_x As Byte
Dim Roi_y As Byte
Dim Roi_center As Byte
Dim Roi_size_enc As Byte
Dim Current_roi As Byte
Current_roi = 16

' LCD display buffers
Dim Lcd_line1 As String * 16
Dim Lcd_line2 As String * 16

' Thresholds for mode switching (in mm)
Const SHORT_RANGE_MAX = 600     ' Switch to MEDIUM above 600mm
Const MEDIUM_RANGE_MAX = 1500   ' Switch to LONG above 1500mm
' Signal thresholds for switching
Const MIN_SIG_SHORT = 400       ' Lowered for better stability
Const MIN_SIG_MEDIUM = 200      ' Lowered for better stability
Const LOW_SIG_THRESHOLD = 100   ' Lowered for better stability

' === DS18B20 TEMPERATURE VARIABLES ===
Dim Temp_lsb As Byte
Dim Temp_msb As Byte
Dim Temperature As Single
Dim Temp_str As String * 6
Dim Temp_display As String * 10
' 1-Wire commands
Const Search_rom = &HF0
Const Read_rom = &H33
Const Match_rom = &H55
Const Skip_rom = &HCC
Const Alarm_search = &HEC
' DS18B20 commands
Const Convert_t = &H44
Const Write_scratchpad = &H4E
Const Read_scratchpad = &HBE
Const Copy_scratchpad = &H48
Const Recla_e2 = &HB8
Const Read_power_supply = &HB4

Device_address_write = &H52  ' 0x29 << 1
Device_address_read = &H53   ' 0x52 + 1

' Initialize LCD
Cls
Lcd "VL53L1X HIGH POWER"
Lowerline
Lcd "Initializing..."
Waitms 1000

Print "=== VL53L1X HIGH-POWER ADAPTIVE ==="
Print "with PCF8563 RTC + DS18B20 Temp"
Print "Auto-switching: SHORT/MEDIUM/LONG"
Print "High-power mode for low signals"
Print "Thresholds: <600mm, 600-1500mm, >1500mm"
Print "ROI commands: R4/R8/R12/R16 (4x4 to 16x16)"
Print "Manual mode: S/M/L/L+ locks mode, AUTO resumes auto-switch"
Print ""

' Test temperature sensor
Cls
Lcd "Testing Temp..."
Lowerline
Lcd "Sensor..."
Gosub Read_temperature
Cls
Lcd "Temp Sensor OK"
Lowerline
Lcd "T:" ; Temp_str ; "{001}C"
Waitms 1000

' === ASK IF USER WANTS TO SET RTC TIME ===
Print "Set RTC time? (Y=Yes, N=No)"
Do
   If Ischarwaiting() = 1 Then
      Dim Key As Byte
      Key = Inkey()
      If Key = 89 Or Key = 121 Then  ' Y or y
         Time_set_flag = 1
         Exit Do
      Elseif Key = 78 Or Key = 110 Then  ' N or n
         Time_set_flag = 0
         Exit Do
      End If
   End If
Loop

If Time_set_flag = 1 Then
   Gosub Set_rtc_time
End If

' Initialize PCF8563 (set CLKOUT to 1Hz)
I2cstart
I2cwbyte &HA2
I2cwbyte &H0D
I2cwbyte &B10000011
I2cstop
Waitms 10

' === VL53L1X INITIALIZATION ===
Gosub Initialize_vl53l1x

' Start with MEDIUM range as default
Current_range_mode = 2  ' MEDIUM
Previous_mode = 0       ' Force display on first call
High_power_active = 0   ' Start in normal power mode
Low_signal_counter = 0
Manual_mode_active = 0  ' Start in auto mode
Gosub Set_range_mode
Range_mode_changed = 0
Wrong_mode_count = 0
Hw_failure_count = 0

' Clear LCD and show ready message
Cls
Lcd "HIGH-POWER MODE"
Lowerline
Lcd "MEDIUM Range"
Waitms 1000

' === MAIN LOOP ===
Measurement_count = 0

Do
   Measurement_count = Measurement_count + 1

  ' === SERIAL COMMAND HANDLER ===
   If Ischarwaiting() = 1 Then
      Dim Cmd_char As Byte
      Dim Cmd_buffer As String * 10
      Cmd_buffer = ""

      ' Read available characters into a small buffer (max 10)
      Do
         Cmd_char = Inkey()
         If Cmd_char = 13 Then Exit Do     ' Enter ends command
         If Cmd_char = 10 Then Exit Do     ' LF ends command
         If Len(cmd_buffer) < 10 Then
            Cmd_buffer = Cmd_buffer + Chr(cmd_char)
         End If
      Loop Until Ischarwaiting() = 0

      ' ---- Process the buffered command ----

      If Cmd_buffer = "RESET" Then
         Print "[RESET COMMAND - REBOOTING...]"
         Waitms 200
         Gosub Reboot_evb

      Elseif Cmd_buffer = "S" Then                     ' SHORT
         Current_range_mode = 1
         Range_mode_changed = 1
         Manual_mode_active = 1                         ' Lock manual mode
         Print "[MANUAL: SHORT mode (locked)]"

      Elseif Cmd_buffer = "M" Then                     ' MEDIUM
         Current_range_mode = 2
         Range_mode_changed = 1
         Manual_mode_active = 1                         ' Lock manual mode
         Print "[MANUAL: MEDIUM mode (locked)]"

      Elseif Cmd_buffer = "L" Then                     ' LONG
         Current_range_mode = 3
         High_power_active = 0
         Range_mode_changed = 1
         Manual_mode_active = 1                         ' Lock manual mode
         Print "[MANUAL: LONG mode (locked)]"

      Elseif Cmd_buffer = "L+" Then                    ' LONG HIGH POWER
         Current_range_mode = 3
         High_power_active = 1
         Range_mode_changed = 1
         Manual_mode_active = 1                         ' Lock manual mode
         Print "[MANUAL: LONG HIGH POWER mode (locked)]"

      Elseif Cmd_buffer = "A" Then                     ' AUTO (short form)
         Manual_mode_active = 0                         ' Unlock auto mode
         Wrong_mode_count = 0
         Low_signal_counter = 0
         Print "[SWITCHING TO AUTO MODE]"

      Elseif Cmd_buffer = "AUTO" Then                  ' AUTO mode
         Manual_mode_active = 0                         ' Unlock auto mode
         Wrong_mode_count = 0
         Low_signal_counter = 0
         Print "[SWITCHING TO AUTO MODE]"

      Elseif Cmd_buffer = "MANUAL" Then                ' MANUAL mode
         Manual_mode_active = 1
         Print "[MANUAL MODE ACTIVE (current settings locked)]"

      Elseif Cmd_buffer = "STATUS" Then                ' STATUS request
         Print "[STATUS: Mode=" ; Current_range_mode ; " HP=" ; High_power_active ; " ROI=" ; Current_roi ; "x" ; Current_roi ; " Manual=" ; Manual_mode_active ; "]"

      Elseif Cmd_buffer = "INFO" Then                  ' INFO request
         Print "[EVB 4.3 v4 | VL53L1X | DS18B20 | PCF8563 | ROI: R4-R16]"

      Elseif Cmd_buffer = "TIME" Then                  ' TIME = set RTC
         Gosub Set_rtc_time

      Elseif Cmd_buffer = "R4" Then                    ' ROI 4x4
         Roi_x = 4 : Roi_y = 4
         Gosub Set_roi

      Elseif Cmd_buffer = "R8" Then                    ' ROI 8x8
         Roi_x = 8 : Roi_y = 8
         Gosub Set_roi

      Elseif Cmd_buffer = "R12" Then                   ' ROI 12x12
         Roi_x = 12 : Roi_y = 12
         Gosub Set_roi

      Elseif Cmd_buffer = "R16" Then                   ' ROI 16x16
         Roi_x = 16 : Roi_y = 16
         Gosub Set_roi

      Elseif Cmd_buffer = "?" Then                     ' HELP
         Print "[CMDS: S M L L+ AUTO R4 R8 R12 R16 STATUS INFO RESET]"
      End If

   End If
   ' === END COMMAND HANDLER ===

   ' Read current time from RTC
   Gosub Read_pcf8563

   ' Read temperature
   Gosub Read_temperature

   ' Perform measurement (VL53L1X code unchanged)
   Gosub Single_measurement

   ' === CHECK IF WE NEED TO SWITCH RANGE MODE ===
   Gosub Check_range_mode_switch

   ' If range mode changed, reconfigure sensor
   If Range_mode_changed = 1 Then
      Range_mode_changed = 0
      Current_range_mode = New_range_mode
      Gosub Set_range_mode

      ' Show mode change on LCD briefly
      Cls
      If Current_range_mode = 1 Then
         Lcd "SWITCHED TO"
         Lowerline
         Lcd "SHORT Range"
      End If
      If Current_range_mode = 2 Then
         Lcd "SWITCHED TO"
         Lowerline
         Lcd "MEDIUM Range"
      End If
      If Current_range_mode = 3 Then
         Lcd "SWITCHED TO"
         Lowerline
         Lcd "LONG Range"
      End If
      Waitms 1000
   End If

   ' === UPDATE LCD DISPLAY ===
   Gosub Update_lcd

   ' === TERMINAL OUTPUT WITH TIMESTAMP AND TEMPERATURE ===
   ' Format: YY-MM-DD HH:MM:SS T:+25.50 #1 [L ] Dist:308mm Sig:556 GOOD

   ' Year - convert BCD to decimal
   Tens = Rtc_year / 16
   Units = Rtc_year And &H0F
   Dec_value = Tens * 10
   Dec_value = Dec_value + Units
   If Dec_value < 10 Then
      Print "0" ; Dec_value ;
   Else
      Print Dec_value ;
   End If
   Print "-" ;

   ' Month
   Tens = Rtc_month / 16
   Units = Rtc_month And &H0F
   Dec_value = Tens * 10
   Dec_value = Dec_value + Units
   If Dec_value < 10 Then
      Print "0" ; Dec_value ;
   Else
      Print Dec_value ;
   End If
   Print "-" ;

   ' Day
   Tens = Rtc_day / 16
   Units = Rtc_day And &H0F
   Dec_value = Tens * 10
   Dec_value = Dec_value + Units
   If Dec_value < 10 Then
      Print "0" ; Dec_value ;
   Else
      Print Dec_value ;
   End If
   Print " " ;

   ' Hour
   Tens = Rtc_hours / 16
   Units = Rtc_hours And &H0F
   Dec_value = Tens * 10
   Dec_value = Dec_value + Units
   If Dec_value < 10 Then
      Print "0" ; Dec_value ;
   Else
      Print Dec_value ;
   End If
   Print ":" ;

   ' Minute
   Tens = Rtc_minutes / 16
   Units = Rtc_minutes And &H0F
   Dec_value = Tens * 10
   Dec_value = Dec_value + Units
   If Dec_value < 10 Then
      Print "0" ; Dec_value ;
   Else
      Print Dec_value ;
   End If
   Print ":" ;

   ' Second
   Tens = Rtc_seconds / 16
   Units = Rtc_seconds And &H0F
   Dec_value = Tens * 10
   Dec_value = Dec_value + Units
   If Dec_value < 10 Then
      Print "0" ; Dec_value ;
   Else
      Print Dec_value ;
   End If

   ' Add temperature
   Print " T:" ; Temp_str ;

   ' Continue with measurement data
   Print " #" ; Measurement_count ; " [" ;

   ' Show current mode
   If Current_range_mode = 1 Then
      Print "S" ;
   End If
   If Current_range_mode = 2 Then
      Print "M" ;
   End If
   If Current_range_mode = 3 Then
      Print "L" ;
   End If

   ' Show power mode
   If High_power_active = 1 Then
      Print "+" ;  ' + indicates high power mode
   Else
      Print " " ;
   End If

   Print "] Dist:" ; Distance ; "mm Sig:" ; Signal_rate ; " " ;

   ' Show status
   If Range_status = &H09 Then
      Print "GOOD"
   End If
   If Range_status = &H07 Then
      Print "LOW*"  ' Asterisk highlights LOW signal
   End If
   If Range_status = &H0B Then
      Print "WRAP"
   End If
   If Range_status = &H01 Then
      Print "FAIL"
   End If
   If Range_status = &H05 Then
      Print "HWF"   ' Hardware failure
   End If
   If Range_status = &H04 Then
      Print "ERR4"  ' Other error
   End If
   If Range_status = &HFF Then
      Print "TIMEO" ' Timeout
   End If
   If Range_status <> &H09 Then
      If Range_status <> &H07 Then
         If Range_status <> &H0B Then
            If Range_status <> &H01 Then
               If Range_status <> &H05 Then
                  If Range_status <> &H04 Then
                     If Range_status <> &HFF Then
                        Print "0x" ; Hex(range_status)
                     End If
                  End If
               End If
            End If
         End If
      End If
   End If

   ' Adaptive wait time based on range mode
   If Current_range_mode = 1 Then  ' SHORT = fast
      Waitms 50
   End If
   If Current_range_mode = 2 Then  ' MEDIUM = medium
      Waitms 100
   End If
   If Current_range_mode = 3 Then  ' LONG = slow
      Waitms 200
   End If

Loop

End

' === READ TEMPERATURE SUBROUTINE ===
Read_temperature:
   1wreset
   1wwrite Skip_rom
   1wwrite Convert_t
   Waitms 750
   1wreset
   1wwrite Skip_rom
   1wwrite Read_scratchpad
   Temp_lsb = 1wread()
   Temp_msb = 1wread()

   ' Convert raw data to temperature
   Temperature = Temp_msb * 256
   Temperature = Temperature + Temp_lsb
   Temperature = Temperature / 16

   ' Handle negative temperatures
   If Temp_msb.7 = 1 Then
      Temperature = Temperature - 4096
   End If

   ' Ultra-simple temperature formatting
   Dim Temp_int As Integer
   Dim Temp_frac As Integer
   Dim Temp_is_negative As Bit
   Dim Digit1 As Byte
   Dim Digit2 As Byte
   Dim Digit3 As Byte
   Dim Digit4 As Byte
   Dim Char1 As Byte
   Dim Char2 As Byte
   Dim Char3 As Byte
   Dim Char4 As Byte

   ' Check if negative
   If Temperature < 0 Then
      Temp_is_negative = 1
      Temperature = 0 - Temperature
   Else
      Temp_is_negative = 0
   End If

   ' Get integer part
   Temp_int = Temperature

   ' Get fractional part (2 digits)
   Temperature = Temperature - Temp_int
   Temperature = Temperature * 100
   Temp_frac = Temperature

   ' Extract digits
   Digit1 = Temp_int / 10
   Digit2 = Temp_int Mod 10
   Digit3 = Temp_frac / 10
   Digit4 = Temp_frac Mod 10

   ' Convert digits to ASCII characters
   Char1 = Digit1
   Char1 = Char1 + 48
   Char2 = Digit2
   Char2 = Char2 + 48
   Char3 = Digit3
   Char3 = Char3 + 48
   Char4 = Digit4
   Char4 = Char4 + 48

   ' Build temperature string
   Temp_str = "00.00"  ' Initialize

   ' Set sign
   If Temp_is_negative = 1 Then
      Temp_str = "-"
   Else
      Temp_str = "+"
   End If

   ' Add integer part digits
   Temp_str = Temp_str + Chr(char1)
   Temp_str = Temp_str + Chr(char2)

   ' Add decimal point
   Temp_str = Temp_str + "."

   ' Add fractional part digits
   Temp_str = Temp_str + Chr(char3)
   Temp_str = Temp_str + Chr(char4)
Return

' === SET RTC TIME SUBROUTINE ===
Set_rtc_time:
   Print "=== SET RTC TIME ==="

   ' Get time from user
   Print "Enter year (00-99): "
   Gosub Wait_for_input
   Input Set_year

   Print "Enter month (1-12): "
   Gosub Wait_for_input
   Input Set_month

   Print "Enter day (1-31): "
   Gosub Wait_for_input
   Input Set_day

   Print "Weekday:"
   For I = 1 To 7
      Print I ; " = " ; Weekday_names(i)
   Next I
   Print "Enter weekday (1-7): "
   Gosub Wait_for_input
   Input Set_weekday

   Print "Enter hour (0-23): "
   Gosub Wait_for_input
   Input Set_hour

   Print "Enter minute (0-59): "
   Gosub Wait_for_input
   Input Set_minute

   Print "Enter second (0-59): "
   Gosub Wait_for_input
   Input Set_second

   ' Convert to BCD manually - break down into separate operations
   ' Year
   Tens = Set_year / 10
   Units = Set_year Mod 10
   Set_year = Tens * 16
   Set_year = Set_year + Units

   ' Month
   Tens = Set_month / 10
   Units = Set_month Mod 10
   Set_month = Tens * 16
   Set_month = Set_month + Units

   ' Day
   Tens = Set_day / 10
   Units = Set_day Mod 10
   Set_day = Tens * 16
   Set_day = Set_day + Units

   ' Hour
   Tens = Set_hour / 10
   Units = Set_hour Mod 10
   Set_hour = Tens * 16
   Set_hour = Set_hour + Units

   ' Minute
   Tens = Set_minute / 10
   Units = Set_minute Mod 10
   Set_minute = Tens * 16
   Set_minute = Set_minute + Units

   ' Second
   Tens = Set_second / 10
   Units = Set_second Mod 10
   Set_second = Tens * 16
   Set_second = Set_second + Units

   Set_weekday = Set_weekday - 1  ' PCF8563 uses 0-6

   ' Write to PCF8563
   I2cstart
   I2cwbyte &HA2
   I2cwbyte 2  ' Start at seconds register
   I2cwbyte Set_second
   I2cwbyte Set_minute
   I2cwbyte Set_hour
   I2cwbyte Set_day
   I2cwbyte Set_weekday
   I2cwbyte Set_month
   I2cwbyte Set_year
   I2cstop

   Print "Time set successfully!"
   Print ""
Return

' === WAIT FOR INPUT SUBROUTINE ===
Wait_for_input:
   ' Wait for serial data
   Do
   Loop Until Ischarwaiting() = 1
Return

' === READ PCF8563 ===
Read_pcf8563:
   I2cstart
   I2cwbyte &HA2
   I2cwbyte 2
   I2cstart
   I2cwbyte &HA3
   I2crbyte Rtc_seconds , Ack
   I2crbyte Rtc_minutes , Ack
   I2crbyte Rtc_hours , Ack
   I2crbyte Rtc_day , Ack
   I2crbyte Rtc_weekday , Ack
   I2crbyte Rtc_month , Ack
   I2crbyte Rtc_year , Nack
   I2cstop

   ' Process data - mask off unused bits
   Rtc_seconds = Rtc_seconds And &H7F
   Rtc_minutes = Rtc_minutes And &H7F
   Rtc_hours = Rtc_hours And &H3F
   Rtc_day = Rtc_day And &H3F
   Rtc_weekday = Rtc_weekday And &H07
   Rtc_month = Rtc_month And &H1F
   Rtc_weekday = Rtc_weekday + 1  ' Convert to 1-7
Return

' === CHECK RANGE MODE SWITCH SUBROUTINE ===
Check_range_mode_switch:
   ' *** MANUAL MODE LOCK ***
   ' If manual mode is active, skip all auto-switching
   If Manual_mode_active = 1 Then
      Return
   End If

   ' Default: stay in current mode
   New_range_mode = Current_range_mode

   ' Check for hardware failures - simplified approach
   If Range_status = &H05 Then
      Goto Is_hardware_failure
   End If
   If Range_status = &H04 Then
      Goto Is_hardware_failure
   End If
   Goto Not_hardware_failure

Is_hardware_failure:
   Hw_failure_count = Hw_failure_count + 1
   If Hw_failure_count >= 5 Then  ' Too many failures
      ' Switch back to MEDIUM mode and disable high power
      If Current_range_mode = 3 Then  ' Only if we're in LONG mode
         New_range_mode = 2  ' Switch to MEDIUM
         Range_mode_changed = 1
         Hw_failure_count = 0
         High_power_active = 0
         Print " [HW FAIL - SWITCH TO MEDIUM]"
      End If
   End If
   Wrong_mode_count = 0
   Low_signal_counter = 0
   Return

Not_hardware_failure:
   Hw_failure_count = 0  ' Reset counter on successful measurement

   ' Check if we need to activate high-power mode - simplified
   If Range_status = &H07 Then
      Goto Check_signal_power
   End If
   If Range_status = &H09 Then
      Goto Check_signal_power
   End If
   Goto Skip_power_check

Check_signal_power:
   If Signal_rate < LOW_SIG_THRESHOLD Then
      If Distance > 0 Then
         Low_signal_counter = Low_signal_counter + 1
         If Low_signal_counter >= 3 Then  ' 3 consecutive low signals
            If High_power_active = 0 Then  ' Only if not already in high power
               High_power_active = 1
               Range_mode_changed = 1  ' Force reconfiguration with high power
               Print " [ACTIVATING HIGH POWER]"
            End If
         End If
      End If
   Else
      ' Signal is good, consider disabling high power
      If High_power_active = 1 Then
         ' Calculate threshold
         Sig_threshold = LOW_SIG_THRESHOLD
         Sig_threshold = Sig_threshold * 2
         If Signal_rate > Sig_threshold Then
            Low_signal_counter = Low_signal_counter - 1
            If Low_signal_counter = 0 Then
               High_power_active = 0
               Range_mode_changed = 1  ' Force reconfiguration with normal power
               Print " [DISABLING HIGH POWER]"
            End If
         Else
            Low_signal_counter = 0
         End If
      End If
   End If
   Goto After_power_check

Skip_power_check:
   Low_signal_counter = 0

After_power_check:

   ' First check signal quality - if signal is LOW, we should increase range immediately
   If Range_status = &H07 Then  ' LOW signal
      If Current_range_mode = 1 Then  ' Currently in SHORT
         New_range_mode = 2     ' Switch to MEDIUM
         Range_mode_changed = 1
         Wrong_mode_count = 0
         Return
      End If
      If Current_range_mode = 2 Then  ' Currently in MEDIUM
         New_range_mode = 3     ' Switch to LONG
         Range_mode_changed = 1
         Wrong_mode_count = 0
         Return
      Else
         ' We're already in LONG mode and still getting LOW signal
         New_range_mode = 3
         Wrong_mode_count = 0
         Return
      End If
   End If

   ' If we timed out, treat as LOW signal
   If Range_status = &HFF Then  ' Timeout
      If Current_range_mode < 3 Then  ' Only increase range if not already at max
         New_range_mode = Current_range_mode + 1
         Range_mode_changed = 1
         Wrong_mode_count = 0
      End If
      Return
   End If

   ' If signal is GOOD or WRAP
   If Range_status = &H09 Then
      Goto Check_good_wrap
   End If
   If Range_status = &H0B Then
      Goto Check_good_wrap
   End If
   Goto Skip_good_wrap

Check_good_wrap:
   ' Check if we can switch to a more optimal mode
   If Distance < SHORT_RANGE_MAX Then
      If Distance > 0 Then
         ' Object is close - SHORT range optimal if signal is strong
         If Current_range_mode > 1 Then
            If Signal_rate > MIN_SIG_SHORT Then  ' Only switch down if signal is strong
               New_range_mode = 1
            End If
         End If
      End If
   End If

   If Distance >= SHORT_RANGE_MAX Then
      If Distance <= MEDIUM_RANGE_MAX Then
         ' Object at medium distance - MEDIUM range optimal
         If Current_range_mode = 3 Then
            If Signal_rate > MIN_SIG_MEDIUM Then  ' Switch from LONG to MEDIUM if signal is good
               New_range_mode = 2
            End If
         End If
         If Current_range_mode = 1 Then  ' Switch from SHORT to MEDIUM for medium distances
            New_range_mode = 2
         End If
      End If
   End If

   If Distance > MEDIUM_RANGE_MAX Then
      ' Object far away - LONG range optimal
      If Current_range_mode < 3 Then
         New_range_mode = 3
      End If
   End If

Skip_good_wrap:

   ' Hysteresis: Only switch if we've been in the "wrong" mode for multiple measurements
   If New_range_mode <> Current_range_mode Then
      Wrong_mode_count = Wrong_mode_count + 1
      If Wrong_mode_count >= 3 Then  ' Need 3 consecutive measurements suggesting change
         Range_mode_changed = 1
         Wrong_mode_count = 0
      End If
   Else
      Wrong_mode_count = 0
   End If
Return

' === SET RANGE MODE SUBROUTINE WITH HIGH-POWER OPTION ===
Set_range_mode:
   ' Only print if mode is actually different from previous mode OR power mode changed
   If Current_range_mode <> Previous_mode Then
      Print "Setting " ;
      If Current_range_mode = 1 Then
         Print "SHORT range mode" ;
      End If
      If Current_range_mode = 2 Then
         Print "MEDIUM range mode" ;
      End If
      If Current_range_mode = 3 Then
         Print "LONG range mode" ;
      End If

      If High_power_active = 1 Then
         Print " (HIGH POWER)..." ;
      Else
         Print "..." ;
      End If
      Print ""  ' Add newline

      Previous_mode = Current_range_mode
   End If

   ' Stop ranging first
   Addr = VL53L1_MODE_START
   Data_byte = &H00
   Gosub Write_8bit
   Waitms 10

   If Current_range_mode = 1 Then
      ' SHORT RANGE settings
      If High_power_active = 1 Then
         ' HIGH POWER SHORT RANGE
         Addr = VL53L1_VCSEL_A : Data_byte = 14 : Gosub Write_8bit : Waitms 10  ' Increased from 12
         Addr = VL53L1_VCSEL_B : Data_byte = 12 : Gosub Write_8bit : Waitms 10  ' Increased from 10
         Addr = VL53L1_TIMEOUT_A_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_LO : Data_byte = &HC8 : Gosub Write_8bit : Waitms 10  ' ~400µs
         Addr = VL53L1_TIMEOUT_B_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_B_LO : Data_byte = &H0A : Gosub Write_8bit : Waitms 10  ' ~24µs
         Addr = VL53L1_INTERMEASURE : Value = &H001E : Gosub Write_16bit : Waitms 10  ' 30ms
      Else
         ' NORMAL POWER SHORT RANGE
         Addr = VL53L1_VCSEL_A : Data_byte = 12 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_VCSEL_B : Data_byte = 10 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_LO : Data_byte = &H9B : Gosub Write_8bit : Waitms 10  ' ~300µs
         Addr = VL53L1_TIMEOUT_B_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_B_LO : Data_byte = &H05 : Gosub Write_8bit : Waitms 10  ' ~12µs
         Addr = VL53L1_INTERMEASURE : Value = &H0014 : Gosub Write_16bit : Waitms 10  ' 20ms
      End If

   Elseif Current_range_mode = 2 Then
      ' MEDIUM RANGE settings
      If High_power_active = 1 Then
         ' HIGH POWER MEDIUM RANGE
         Addr = VL53L1_VCSEL_A : Data_byte = 20 : Gosub Write_8bit : Waitms 10  ' Increased from 18
         Addr = VL53L1_VCSEL_B : Data_byte = 16 : Gosub Write_8bit : Waitms 10  ' Increased from 14
         Addr = VL53L1_TIMEOUT_A_HI : Data_byte = &H01 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_LO : Data_byte = &H2C : Gosub Write_8bit : Waitms 10  ' ~3000µs
         Addr = VL53L1_TIMEOUT_B_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_B_LO : Data_byte = &H14 : Gosub Write_8bit : Waitms 10  ' ~50µs
         Addr = VL53L1_INTERMEASURE : Value = &H0046 : Gosub Write_16bit : Waitms 10  ' 70ms
      Else
         ' NORMAL POWER MEDIUM RANGE
         Addr = VL53L1_VCSEL_A : Data_byte = 18 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_VCSEL_B : Data_byte = 14 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_LO : Data_byte = &HFE : Gosub Write_8bit : Waitms 10  ' ~500µs
         Addr = VL53L1_TIMEOUT_B_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_B_LO : Data_byte = &H08 : Gosub Write_8bit : Waitms 10  ' ~20µs
         Addr = VL53L1_INTERMEASURE : Value = &H0032 : Gosub Write_16bit : Waitms 10  ' 50ms
      End If

   Else
      ' LONG RANGE settings
      If High_power_active = 1 Then
         ' HIGH POWER LONG RANGE (MAXIMUM)
         Addr = VL53L1_VCSEL_A : Data_byte = 22 : Gosub Write_8bit : Waitms 10  ' Maximum safe value
         Addr = VL53L1_VCSEL_B : Data_byte = 18 : Gosub Write_8bit : Waitms 10  ' Maximum safe value
         Addr = VL53L1_TIMEOUT_A_HI : Data_byte = &H02 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_LO : Data_byte = &HFF : Gosub Write_8bit : Waitms 10  ' ~16383µs
         Addr = VL53L1_TIMEOUT_B_HI : Data_byte = &H01 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_B_LO : Data_byte = &H2C : Gosub Write_8bit : Waitms 10  ' ~3000µs
         Addr = VL53L1_INTERMEASURE : Value = &H0190 : Gosub Write_16bit : Waitms 10  ' 400ms
      Else
         ' NORMAL POWER LONG RANGE
         Addr = VL53L1_VCSEL_A : Data_byte = 22 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_VCSEL_B : Data_byte = 18 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_HI : Data_byte = &H01 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_A_LO : Data_byte = &H2C : Gosub Write_8bit : Waitms 10  ' ~3000µs
         Addr = VL53L1_TIMEOUT_B_HI : Data_byte = &H00 : Gosub Write_8bit : Waitms 10
         Addr = VL53L1_TIMEOUT_B_LO : Data_byte = &H1E : Gosub Write_8bit : Waitms 10  ' ~60µs
         Addr = VL53L1_INTERMEASURE : Value = &H00C8 : Gosub Write_16bit : Waitms 10  ' 200ms
      End If
   End If

   ' Set HV_CONFIG based on power mode
   Addr = VL53L1_HV_CONFIG
   If High_power_active = 1 Then
      Data_byte = &H03  ' High power setting
   Else
      Data_byte = &H01  ' Normal power setting
   End If
   Gosub Write_8bit
   Waitms 10

   ' Always reconfigure interrupts
   Addr = VL53L1_INT_CONFIG
   Data_byte = &H24
   Gosub Write_8bit
   Waitms 10

   ' Clear any pending interrupt
   Addr = VL53L1_INT_CLEAR
   Data_byte = &H01
   Gosub Write_8bit
   Waitms 10

   ' Restart ranging
   Addr = VL53L1_MODE_START
   Data_byte = &H40
   Gosub Write_8bit

   ' Longer wait for high power mode or LONG range
   If High_power_active = 1 Then
      Waitms 300
   Else
      If Current_range_mode = 3 Then
         Waitms 300
      Else
         Waitms 200
      End If
   End If
Return

' === SET ROI SUBROUTINE ===
Set_roi:
   ' Calculate center SPAD and size encoding
   If Roi_x = 16 Then
      Roi_center = 199
      Roi_size_enc = &H0F   ' 16x16
   Elseif Roi_x = 12 Then
      Roi_center = 183
      Roi_size_enc = &H33   ' 12x12
   Elseif Roi_x = 8 Then
      Roi_center = 135
      Roi_size_enc = &H22   ' 8x8
   Elseif Roi_x = 4 Then
      Roi_center = 71
      Roi_size_enc = &H11   ' 4x4
   Else
      Print "[ROI Error: use 4, 8, 12, or 16]"
      Return
   End If

   ' Write ROI center
   Addr = VL53L1_ROI_CENTRE
   Data_byte = Roi_center
   Gosub Write_8bit
   Waitms 5

   ' Write ROI size
   Addr = VL53L1_ROI_SIZE
   Data_byte = Roi_size_enc
   Gosub Write_8bit
   Waitms 5

   ' Restart ranging
   Addr = VL53L1_MODE_START
   Data_byte = &H00  ' Stop
   Gosub Write_8bit
   Waitms 10
   Addr = VL53L1_MODE_START
   Data_byte = &H40  ' Start
   Gosub Write_8bit

   Current_roi = Roi_x
   Print "[ROI: " ; Roi_x ; "x" ; Roi_y ; " (Center:" ; Roi_center ; ")]"
Return

' === LCD UPDATE SUBROUTINE ===
Update_lcd:
   ' Line 1: Distance and range mode and signal
   Dim Mode_char As String * 1
   If Current_range_mode = 1 Then
      Mode_char = "S"
   End If
   If Current_range_mode = 2 Then
      Mode_char = "M"
   End If
   If Current_range_mode = 3 Then
      Mode_char = "L"
   End If

   ' Add power mode indicator
   Dim Power_char As String * 1
   If High_power_active = 1 Then
      Power_char = "+"
   Else
      Power_char = " "
   End If

   ' Line 1: L:308mm S:556 (or S:308mm S:556, M:308mm S:556, L:308mm S:556)
   Lcd_line1 = Mode_char + Power_char + ":" + Str(distance) + "mm S:" + Str(signal_rate)

   ' Pad to 16 characters
   While Len(lcd_line1) < 16
      Lcd_line1 = Lcd_line1 + " "
   Wend

   ' Line 2: Temperature alone
   ' Format: "T:+25.50°C"
   Temp_display = "T:" + Temp_str + "{001}C"

   ' Pad to 16 characters
   While Len(temp_display) < 16
      Temp_display = Temp_display + " "
   Wend

   Lcd_line2 = Temp_display

   ' Update LCD
   Cls
   Lcd Lcd_line1
   Lowerline
   Lcd Lcd_line2
Return

' === INITIALIZATION SUBROUTINE ===
Initialize_vl53l1x:
   Print "Initializing VL53L1X..."

   ' Hardware reset
   Shut = 0
   Waitms 100
   Shut = 1
   Waitms 1000

   ' Check sensor
   Addr = VL53L1_MODEL_ID
   Gosub Read_16bit
   Print "Sensor: VL53L1X (0x" ; Hex(data_high) ; Hex(data_low) ; ")"
   Print "HIGH-POWER ADAPTIVE MODE"
   Print "Short <600mm, Medium 600-1500mm, Long >1500mm"
   Print "High-power activation on low signal (<" ; LOW_SIG_THRESHOLD ; ")"
   Print "ROI: R4/R8/R12/R16 (4x4 to 16x16)"
   Print "Manual mode: S/M/L/L+ locks, AUTO resumes"
   Print ""

   ' Basic configuration (common to all modes)
   Addr = VL53L1_FIRMWARE_EN : Data_byte = &H01 : Gosub Write_8bit : Waitms 10
   Addr = VL53L1_POWER_FORCE : Data_byte = &H01 : Gosub Write_8bit : Waitms 10
   Addr = VL53L1_HV_CONFIG   : Data_byte = &H01 : Gosub Write_8bit : Waitms 10  ' Start with normal power
   Addr = VL53L1_ROI_CENTRE  : Data_byte = 199  : Gosub Write_8bit : Waitms 10
   Addr = VL53L1_ROI_SIZE    : Data_byte = 15   : Gosub Write_8bit : Waitms 10   ' Default 16x16
   Addr = VL53L1_INT_CONFIG  : Data_byte = &H24 : Gosub Write_8bit : Waitms 10

   Print "Base configuration complete! (High-Power Mode Ready)"
   Print "ROI commands: R4 R8 R12 R16"
   Waitms 500
Return

' === SINGLE MEASUREMENT SUBROUTINE ===
Single_measurement:
   ' Reset status variable
   Range_status = 0

   ' Clear any old interrupt
   Addr = VL53L1_INT_CLEAR
   Data_byte = &H01
   Gosub Write_8bit
   Waitms 10

   ' Start single measurement
   Addr = VL53L1_MODE_START
   Data_byte = &H40
   Gosub Write_8bit

   ' Wait for measurement (timeout depends on current mode and power setting)
   Loop_cnt = 0
   Dim Timeout_limit As Word

   ' Set timeout based on current mode and power setting
   If Current_range_mode = 1 Then  ' SHORT = fast
      If High_power_active = 1 Then
         Timeout_limit = 120  ' 600ms for high power
      Else
         Timeout_limit = 100  ' 500ms for normal power
      End If
   Elseif Current_range_mode = 2 Then  ' MEDIUM
      If High_power_active = 1 Then
         Timeout_limit = 180  ' 900ms for high power
      Else
         Timeout_limit = 150  ' 750ms for normal power
      End If
   Else  ' LONG
      If High_power_active = 1 Then
         Timeout_limit = 250  ' 1250ms for high power
      Else
         Timeout_limit = 200  ' 1000ms for normal power
      End If
   End If

   Do
      Addr = VL53L1_INT_STATUS
      Gosub Read_8bit
      If Data_byte.0 = 1 Then Exit Do
      Waitms 5
      Loop_cnt = Loop_cnt + 1
      If Loop_cnt > Timeout_limit Then  ' Mode and power dependent timeout
         ' Timeout occurred
         Range_status = &HFF  ' Special code for timeout
         Distance = 0
         Signal_rate = 0
         Ambient_rate = 0

         ' Reset sensor state after timeout
         Addr = VL53L1_MODE_START
         Data_byte = &H00
         Gosub Write_8bit
         Waitms 50

         Exit Do
      End If
   Loop

   ' Only read measurements if we didn't timeout
   If Range_status <> &HFF Then
      ' Read status
      Addr = VL53L1_RANGE_STATUS
      Gosub Read_8bit
      Range_status = Data_byte

      ' Check if status indicates a problem
      If Range_status = &H05 Then
         Goto Status_error
      End If
      If Range_status = &H04 Then  ' Hardware failure or other error
Status_error:
         ' Don't try to read distance, just return zeros
         Distance = 0
         Signal_rate = 0
         Ambient_rate = 0
         Goto After_status_check
      End If

      ' Always read the measurements even if status is not perfect
      ' This clears the data registers
      Addr = VL53L1_DISTANCE_SD0
      Gosub Read_16bit
      Distance = Value

      Addr = VL53L1_PEAK_SIGNAL_SD0
      Gosub Read_16bit
      Signal_rate = Value

      Addr = VL53L1_AMBIENT_SD0
      Gosub Read_16bit
      Ambient_rate = Value

      ' If status is really bad, set distance to 0
      If Range_status = &H01 Then  ' FAIL
         Distance = 0
         Signal_rate = 0
      End If

      Goto After_status_check
   End If

After_status_check:

   ' Clear interrupt
   Addr = VL53L1_INT_CLEAR
   Data_byte = &H01
   Gosub Write_8bit

   ' Stop ranging to prepare for next measurement
   Addr = VL53L1_MODE_START
   Data_byte = &H00
   Gosub Write_8bit
   Waitms 10
Return

' === I2C SUBROUTINES ===

Write_8bit:
   I2cstart
   I2cwbyte Device_address_write
   I2cwbyte High(addr)
   I2cwbyte Low(addr)
   I2cwbyte Data_byte
   I2cstop
   Waitms 2
Return

Write_16bit:
   I2cstart
   I2cwbyte Device_address_write
   I2cwbyte High(addr)
   I2cwbyte Low(addr)
   I2cwbyte High(value)
   I2cwbyte Low(value)
   I2cstop
   Waitms 2
Return

Read_8bit:
   I2cstart
   I2cwbyte Device_address_write
   I2cwbyte High(addr)
   I2cwbyte Low(addr)
   I2cstart
   I2cwbyte Device_address_read
   I2crbyte Data_byte , Nack
   I2cstop
   Waitms 2
Return

Read_16bit:
   I2cstart
   I2cwbyte Device_address_write
   I2cwbyte High(addr)
   I2cwbyte Low(addr)
   I2cstart
   I2cwbyte Device_address_read
   I2crbyte Data_high , Ack
   I2crbyte Data_low , Nack
   I2cstop

   Value = Data_high * 256
   Value = Value + Data_low
   Waitms 2
Return

' === RESET I2C BUS SUBROUTINE ===
Reset_i2c_bus:
   ' Release SCL and SDA
   Config Sda = Portc.1
   Config Scl = Portc.0
   Portc.0 = 1  ' SCL high
   Portc.1 = 1  ' SDA high

   ' Generate 9 clock pulses
   For I = 1 To 9
      Portc.0 = 0
      Waitus 5
      Portc.0 = 1
      Waitus 5
   Next I

   ' Send STOP condition
   Portc.0 = 1
   Portc.1 = 0
   Waitus 5
   Portc.0 = 0
   Waitus 5
   Portc.1 = 1
   Waitus 5
   Portc.0 = 1
   Waitus 5

   ' Reconfigure I2C
   Config Sda = Portc.1
   Config Scl = Portc.0
   I2cinit
   Twbr = 72
Return

' === REBOOT EVB SUBROUTINE (WATCHDOG) ===
Reboot_evb:
   Print "[Watchdog reset...]"
   ' Reset watchdog timer
   Wdtcr = &B00011000      ' Enable config change
   Wdtcr = &B00001000      ' WDE=1, ~16ms timeout at 16MHz
   ' Wait indefinitely - watchdog will reset the MCU
   Do
   Loop
Return
