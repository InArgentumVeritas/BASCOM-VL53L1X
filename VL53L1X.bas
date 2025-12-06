$regfile = "m644pdef.dat"
$crystal = 16000000
$baud = 9600

' === LCD CONFIGURATION ===
Config Lcdpin = Pin , Db4 = Portc.4 , Db5 = Portc.5 , Db6 = Portc.6 , Db7 = Portc.7 , E = Portc.3 , Rs = Portc.2
Config Lcd = 16 * 2
Cursor Off

' Configure SHUT pin for hardware reset
Config PinD.2 = Output  ' SHUT/Reset pin
Shut Alias PortD.2

Config Sda = Portc.1
Config Scl = Portc.0
Twbr = 12

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

' Variables
Dim Device_address_write As Byte
Dim Device_address_read As Byte
Dim Temp_byte As Byte
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

' Range mode tracking
Dim Current_range_mode As Byte  ' 1=SHORT, 2=MEDIUM, 3=LONG
Dim New_range_mode As Byte
Dim Range_mode_changed As Bit
Dim Wrong_mode_count As Byte  ' Hysteresis counter
Dim Hw_failure_count As Byte   ' Hardware failure counter
Dim Previous_mode As Byte      ' Track previous mode for display
Dim Low_signal_counter As Byte ' Count consecutive LOW signals
Dim High_power_active As Bit   ' Flag for high-power mode

' LCD display buffers
Dim Lcd_line1 As String * 16
Dim Lcd_line2 As String * 16

' Thresholds for mode switching (in mm)
Const SHORT_RANGE_MAX = 600     ' Switch to MEDIUM above 600mm
Const MEDIUM_RANGE_MAX = 1500   ' Switch to LONG above 1500mm
' Signal thresholds for switching
Const MIN_SIG_SHORT = 800       ' Increased for high-power mode
Const MIN_SIG_MEDIUM = 500      ' Increased for high-power mode
Const LOW_SIG_THRESHOLD = 300   ' Signal below this triggers high-power mode

Device_address_write = &H52  ' 0x29 << 1
Device_address_read = &H53   ' 0x52 + 1

' Initialize LCD
Cls
Lcd "VL53L1X HIGH POWER"
Lowerline
Lcd "Initializing..."
Waitms 1000

Print "=== VL53L1X HIGH-POWER ADAPTIVE ==="
Print "Auto-switching: SHORT/MEDIUM/LONG"
Print "High-power mode for low signals"
Print "Thresholds: <600mm, 600-1500mm, >1500mm"
Print ""

' === INITIALIZATION ===
Gosub Initialize_vl53l1x

' Start with MEDIUM range as default
Current_range_mode = 2  ' MEDIUM
Previous_mode = 0       ' Force display on first call
High_power_active = 0   ' Start in normal power mode
Low_signal_counter = 0
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

   ' Perform measurement
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

   ' === TERMINAL OUTPUT - SIMPLIFIED ===
   Print "#" ; Measurement_count ;

   ' Show current mode
   Print " [" ;
   If Current_range_mode = 1 Then
      Print "S"
   End If
   If Current_range_mode = 2 Then
      Print "M"
   End If
   If Current_range_mode = 3 Then
      Print "L"
   End If

   ' Show power mode
   If High_power_active = 1 Then
      Print "+" ;  ' + indicates high power mode
   Else
      Print " " ;
   End If

   Print "] " ;

   Print "Dist:" ; Distance ; "mm " ;
   Print "Sig:" ; Signal_rate ; " " ;

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

   Print ""

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

' === CHECK RANGE MODE SWITCH SUBROUTINE ===
Check_range_mode_switch:
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
         Print " (HIGH POWER)..."
      Else
         Print "..."
      End If

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

' === LCD UPDATE SUBROUTINE ===
Update_lcd:
   ' Line 1: Distance and range mode
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

   Lcd_line1 = Mode_char + Power_char + ":" + Str(distance) + "mm"

   ' Pad to 16 characters
   While Len(lcd_line1) < 16
      Lcd_line1 = Lcd_line1 + " "
   Wend

   ' Line 2: Signal and status
   Dim Status_text As String * 5
   If Range_status = &H09 Then
      Status_text = "GOOD "
   End If
   If Range_status = &H07 Then
      Status_text = "LOW* "  ' Highlight LOW signal
   End If
   If Range_status = &H0B Then
      Status_text = "WRAP "
   End If
   If Range_status = &H01 Then
      Status_text = "FAIL "
   End If
   If Range_status = &H05 Then
      Status_text = "HWF "
   End If
   If Range_status = &H04 Then
      Status_text = "ERR4 "
   End If
   If Range_status = &HFF Then
      Status_text = "TIMEO"
   End If
   If Range_status <> &H09 Then
      If Range_status <> &H07 Then
         If Range_status <> &H0B Then
            If Range_status <> &H01 Then
               If Range_status <> &H05 Then
                  If Range_status <> &H04 Then
                     If Range_status <> &HFF Then
                        Status_text = "0x" + Hex(range_status)
                     End If
                  End If
               End If
            End If
         End If
      End If
   End If

   ' Make sure status_text is at least 5 characters
   While Len(status_text) < 5
      Status_text = Status_text + " "
   Wend

   Lcd_line2 = "Sig:" + Str(signal_rate) + " " + Status_text

   ' Pad to 16 characters
   While Len(lcd_line2) < 16
      Lcd_line2 = Lcd_line2 + " "
   Wend

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
   Print ""

   ' Basic configuration (common to all modes)
   Addr = VL53L1_FIRMWARE_EN : Data_byte = &H01 : Gosub Write_8bit : Waitms 10
   Addr = VL53L1_POWER_FORCE : Data_byte = &H01 : Gosub Write_8bit : Waitms 10
   Addr = VL53L1_HV_CONFIG   : Data_byte = &H01 : Gosub Write_8bit : Waitms 10  ' Start with normal power
   Addr = VL53L1_ROI_CENTRE  : Data_byte = 199  : Gosub Write_8bit : Waitms 10
   Addr = VL53L1_ROI_SIZE    : Data_byte = 15   : Gosub Write_8bit : Waitms 10
   Addr = VL53L1_INT_CONFIG  : Data_byte = &H24 : Gosub Write_8bit : Waitms 10

   Print "Base configuration complete! (High-Power Mode Ready)"
   Waitms 500
Return

' === SINGLE MEASUREMENT SUBROUTINE ===
Single_measurement:
   ' Stop any previous ranging
   Addr = VL53L1_MODE_START
   Data_byte = &H00
   Gosub Write_8bit
   Waitms 10

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
      If Range_status = &H09 Then
         Goto Valid_status
      End If
      If Range_status = &H07 Then
         Goto Valid_status
      End If
      If Range_status = &H0B Then  ' Valid status
Valid_status:
         ' Valid status, read measurements
         Addr = VL53L1_DISTANCE_SD0
         Gosub Read_16bit
         Distance = Value

         Addr = VL53L1_PEAK_SIGNAL_SD0
         Gosub Read_16bit
         Signal_rate = Value

         Addr = VL53L1_AMBIENT_SD0
         Gosub Read_16bit
         Ambient_rate = Value
         Goto After_status_check
      Else
         ' Other status codes
         Distance = 0
         Signal_rate = 0
         Ambient_rate = 0
      End If
   End If

After_status_check:

   ' Clear interrupt
   Addr = VL53L1_INT_CLEAR
   Data_byte = &H01
   Gosub Write_8bit
Return

' === I2C SUBROUTINES ===
Write_8bit:
   Gosub I2c_start
   Temp_byte = Device_address_write
   Gosub I2c_write
   Temp_byte = High(addr)
   Gosub I2c_write
   Temp_byte = Low(addr)
   Gosub I2c_write
   Temp_byte = Data_byte
   Gosub I2c_write
   Gosub I2c_stop
   Waitms 2
Return

Write_16bit:
   Gosub I2c_start
   Temp_byte = Device_address_write
   Gosub I2c_write
   Temp_byte = High(addr)
   Gosub I2c_write
   Temp_byte = Low(addr)
   Gosub I2c_write
   Temp_byte = High(value)
   Gosub I2c_write
   Temp_byte = Low(value)
   Gosub I2c_write
   Gosub I2c_stop
   Waitms 2
Return

Read_8bit:
   Gosub I2c_start
   Temp_byte = Device_address_write
   Gosub I2c_write
   Temp_byte = High(addr)
   Gosub I2c_write
   Temp_byte = Low(addr)
   Gosub I2c_write
   Gosub I2c_stop
   Waitms 2

   Gosub I2c_start
   Temp_byte = Device_address_read
   Gosub I2c_write
   Gosub I2c_read_nack
   Data_byte = Twdr
   Gosub I2c_stop
Return

Read_16bit:
   Gosub I2c_start
   Temp_byte = Device_address_write
   Gosub I2c_write
   Temp_byte = High(addr)
   Gosub I2c_write
   Temp_byte = Low(addr)
   Gosub I2c_write
   Gosub I2c_stop
   Waitms 2

   Gosub I2c_start
   Temp_byte = Device_address_read
   Gosub I2c_write
   Gosub I2c_read_ack
   Data_high = Twdr
   Gosub I2c_read_nack
   Data_low = Twdr
   Gosub I2c_stop

   Value = Data_high * 256
   Value = Value + Data_low
Return

' === I2C LOW-LEVEL SUBROUTINES ===
I2c_start:
   Twcr = &B10100100
   Waitus 10
I2c_start_wait:
   If Twcr.7 = 0 Then Goto I2c_start_wait
Return

I2c_write:
   Twdr = Temp_byte
   Twcr = &B10000100
   Waitus 10
I2c_write_wait:
   If Twcr.7 = 0 Then Goto I2c_write_wait
Return

I2c_read_ack:
   Twcr = &B11000100
   Waitus 10
I2c_read_ack_wait:
   If Twcr.7 = 0 Then Goto I2c_read_ack_wait
Return

I2c_read_nack:
   Twcr = &B10000100
   Waitus 10
I2c_read_nack_wait:
   If Twcr.7 = 0 Then Goto I2c_read_nack_wait
Return

I2c_stop:
   Twcr = &B10010100
   Waitms 1
Return
