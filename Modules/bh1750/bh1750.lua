--[[ 

##### I²C Module for the BH1750FVI Digital Light Sensor #####


~~ Datasheets ~~


The following sources were of use for reference:



##### Public Function Reference #####
* 

##### Required Firmware Modules #####
i2c, tmr

##### Max RAM usage: 6.7Kb #####

##### Version History #####
- 11/10/2016 JGM - Version 0.1:
    - Initial version

- 11/22/2016 JGM - Version 0.2: 
    - Removed the requirement of the bit firmware module to save some RAM

- 11/28/2016 JGM - Version 0.3:
    - Now uses dynamic timers for all timer-related stuff.  
      This avoids conflicts, but requires a recent firmware

- 2/22/2017 JGM - Version 0.4:
    - Added a check to the init function to see if the sensor was found
    - Added a local variable for i2c_id in case there are multiple i2c buses 
      in the future

--]]


-- ############### Module Initiation ###############


-- Make a table called M, this becomes the class
local M = {}


-- ############### Local variables ###############


-- Local variables
local address, cursor
local sensitivity, resolution, delay
local MTReg, modeCode
local i2c_id = 0


-- ############### Private Functions ###############


-- I²C function to write an Opcode to the device
-- We use this to write configuration settings
local function write(address, opcode)

    --print(address)
    --print(opcode)

    -- Send an I²C start condition
    i2c.start(i2c_id)

    -- Setup I²C address in write mode
    i2c.address(i2c_id, 0x23, i2c.TRANSMITTER)

    -- Write the Opcode
    i2c.write(i2c_id, opcode)

    -- Send an I²C stop condition
    i2c.stop(i2c_id)

end


local function read()

	local lux, bytes, MSB, LSB, intensity

  
    -- Send an I²C start condition
    i2c.start(i2c_id)

    -- Setup I²C address in write mode
    i2c.address(i2c_id, 0x23, i2c.RECEIVER)

	-- Receive two bytes from the sensor
	bytes = i2c.read(i2c_id, 2)

	-- Send an I²C stop condition
	i2c.stop(i2c_id)

	-- Get first byte (most significant, leftmost)
	MSB = string.byte(bytes, 1)

	-- Get the second byte (least significant, rightmost)
	LSB = string.byte(bytes, 2)

	-- Shift the first byte left 8 spaces and add the second byte to it
	--MSB = bit.lshift(MSB, 8)
	--intensity = MSB + LSB
	intensity = MSB * 256 + LSB

    --print("MSB: " .. MSB * 256 .. " | " .. "LSB:" .. LSB .. " | " .. intensity)
    --print("MTReg: " .. MTReg .. " | " .. "Res: " .. resolution)

	-- Check to see if we've changed the sensitivity. 
	if sensitivity ~= 1 then

		-- According to datasheet, divide by 1.2 & multiply by Resolution
		-- Sensitivity has been changed, so don't re-scale
		lux = intensity / 1.2 * resolution

	else

		-- According to datasheet, divide by 1.2 & multiply by Resolution
		-- Rescale to account for Measurement Time change
		lux = intensity / 1.2 * resolution * 69.0 / MTReg

	end

	-- TODO: Check for errors

	return lux

end


-- ############### Public Functions ###############


function M.init(sda, scl, addr, mode)

	-- Restrict address to 0x23 or 0x5C, and default to 0x5C if not specified
	address = addr ~= nil and (addr == 0x23 or addr == 0x5C) and addr or 0x5C

    -- Initialize the I²C bus using the specified pins
    i2c.setup(i2c_id, sda, scl, i2c.SLOW)

	-- Turn on the sensor
	M.on()

	-- Set the mode, defaults to Continuous_H if not set
	M.setMode(mode)

    -- Set defaults for MTReg and Sensitivity
    MTReg = 69
    sensitivity = 1.00
    resolution = 1
    delay = 185

    -- Send an I²C start condition
    -- Test to see if the I²C address works
    i2c.start(i2c_id)

    -- Setup the I²C address in write mode and return any acknowledgment
    local test = i2c.address(i2c_id, address, i2c.TRANSMITTER)

    -- Send an I²C start condition
    i2c.stop(i2c_id)

    -- If we got an acknowledgement (test = true) then we've found the device
    return test

end


-- Turn sensor on
function M.on()

	write(address, 0x01)

end


-- Turn sensor off
-- Reset operator won't work in this mode
function M.off()

	write(address, 0x00)

end


-- Reset the data register value
function M.reset()

	write(address, 0x07)

end


-- Set the sensor mode: continuous or one-time, and 3 sensitivities
function M.setMode(mode)


	if mode == "Continuous_H" then

		-- 1 lx resolution (16 bit), 120ms sampling time
		modeCode = 0x10

	elseif mode == "Continuous_H2" then

		-- 0.5 lx resolution (18 bit), 120ms sampling time
		modeCode = 0x11
		resolution = 0.5

	elseif mode == "Continuous_L" then

		-- 4 lx resolution (15 bit), 16ms sampling time
		modeCode = 0x13
		delay = 25

	elseif mode == "OneTime_H" then

		modeCode = 0x20

	elseif mode == "OneTime_H2" then

		modeCode = 0x21
		resolution = 0.5

	elseif mode == "OneTime_L" then

		modeCode = 0x23
		delay = 25

	else

		-- Default to Continuous_H
		modeCode = 0x10

	end

	-- Write the opcode
	write(address, modeCode)


end


-- Sets the measurement time register for the sensor
-- This allows for adjusting the sensitivity
-- It also allows for extension of the sensor's range.
-- Default is 69, range is from 31 to 254
function M.setMeasurementTime(MT)

	-- Constrain measurment time to [31,254]
	MT = math.min(math.max(MT, 31), 254)

	-- Set the MTReg class variable so we can account for it while measuring
	MTReg = MT

	-- Shift the first 3 bytes of MT to the last 3
	-- Then add the 01000 prefix by adding 0x40
	local high = math.floor(MT / 32) + 0x40
	--local high = bit.rshift(MT, 5) + 0x40

	-- Get rid of the first 3 bytes in MT by ANDing 0x1F
	-- Then add the 011 prefix by adding 0x60
	local low = (MT % 32) + 0x60
	--local low = bit.band(MT, 0x1F) + 0x60

    -- Send an I²C start condition
    i2c.start(i2c_id)

    -- Setup I²C address in write mode
    i2c.address(i2c_id, 0x23, i2c.TRANSMITTER)

    -- Write the high byte
    i2c.write(i2c_id, high)

    -- Write the high byte
    i2c.write(i2c_id, low)

    -- Send an I²C stop condition
    i2c.stop(i2c_id)

end


-- Scales the sensitivity of the sensor by changing measurement time w/o re-scaling
-- Increasing the sensitivity accounts for something covering sensor (window)
-- Decreasing the sensitivity accounts 
-- The range in sensitivity scaling is 0.45 to 3.68.  Default is 1.00
--- void SetSensitivity(float Sens);


function M.getLux(callback_func)

	local lux

	-- Set the mode/initiate a conversion
	write(address, modeCode)

    -- Check if the first optional argument is a function
    -- If so, we have a callback function to run
    if type(callback_func) == "function" then

		-- Read the value after the specified delay is up
        tmr.create():alarm(delay, tmr.ALARM_SINGLE, function()

        	-- Get the lux value
        	lux = read()

        	-- Run the callback function with the lux as the argument
            callback_func(lux)
    	end)

    else

    	-- Get the lux value
    	lux = read()

    	-- Return the lux value, since there is no callback function
    	return(lux)

    end

end


-- Return the module table
return M
