from array import array
import pyaudio
import subprocess
import sys
import logging
import time
import socket

log_file="/home/choco/.log/detect_audio.log"

# Create a very direct logging approach
class DirectLogger:
    def __init__(self, log_file):
        self.log_file = log_file
        # Open the file in append mode with line buffering
        self.file = open(log_file, 'a', buffering=1)
        
    def _log(self, level, message):
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        log_entry = f"{timestamp} - {level} - {message}\n"
        # Write to both stdout and the file
        print(log_entry, end='')
        self.file.write(log_entry)
        self.file.flush()  # Force flush after each write
        
    def info(self, message):
        self._log('INFO', message)
        
    def error(self, message):
        self._log('ERROR', message)
        
    def warning(self, message):
        self._log('WARNING', message)
        
    def debug(self, message):
        self._log('DEBUG', message)

# Create our logger instance
logger = DirectLogger(log_file)

# Audio detection parameters
START_THRESHOLD = 1200  # Threshold for starting playback
STOP_THRESHOLD = 100   # Threshold for stopping playback
MIN_SILENT_PERIODS = 10  # Number of consecutive silent chunks before stopping
MIN_ACTIVE_SAMPLES = 3  # Number of samples above threshold in a single chunk to trigger
CHUNK_SIZE = 4096
FORMAT = pyaudio.paInt16
RATE = 48000
CALIBRATION_SAMPLES = 10  # Number of samples to use for calibration
NOISE_MARGIN = 2.0  # Multiplier for noise floor

# Streaming parameters
hifipi_ip="10.30.40.100"
ls_stream="Turntable_stream"

def is_silent(snd_data, threshold):
    """
    Returns 'True' if below the 'silent' threshold"
    :param snd_data: Audio data array
    :param threshold: Silence threshold
    :return: True|False
    """
    # Get the peak value
    peak = max(abs(x) for x in snd_data)
    
    # Return true if peak is below threshold
    return peak < threshold

def count_samples_above_threshold(snd_data, threshold):
    """
    Count how many samples in the chunk are above the threshold
    :param snd_data: Audio data array
    :param threshold: Threshold to compare against
    :return: Count of samples above threshold
    """
    return sum(1 for x in snd_data if abs(x) >= threshold)


def calibrate_noise_floor(p):
    """
    Measure the ambient noise level to set dynamic thresholds
    """
    logger.info("Calibrating noise floor...")
    
    try:
        # Open stream with exception_on_overflow=False to prevent errors
        stream = p.open(format=FORMAT, channels=2, rate=RATE, input=True, 
                      output=False, frames_per_buffer=CHUNK_SIZE)
        
        # Take several samples to determine the noise floor
        noise_levels = []
        for i in range(CALIBRATION_SAMPLES):
            try:
                # Use exception_on_overflow=False to prevent errors
                snd_data = array('h', stream.read(CHUNK_SIZE, exception_on_overflow=False))
                if sys.byteorder == 'big':
                    snd_data.byteswap()
                if len(snd_data) > 0:  # Make sure we got valid data
                    noise_levels.append(max(abs(x) for x in snd_data))
            except Exception as e:
                logger.error(f"Error during calibration sample {i}: {e}")
            time.sleep(0.1)
        
        stream.stop_stream()
        stream.close()
        
        # Calculate the average noise level if we have samples
        if noise_levels:
            avg_noise = sum(noise_levels) / len(noise_levels)
            logger.info(f"Ambient noise floor: {avg_noise}")
            
            # Set dynamic thresholds based on noise floor
            dynamic_start = max(START_THRESHOLD, int(avg_noise * NOISE_MARGIN))
            dynamic_stop = max(STOP_THRESHOLD, int(avg_noise * 1.2))
            
            return dynamic_start, dynamic_stop
        else:
            logger.warning("Could not calibrate noise floor, using default thresholds")
            return START_THRESHOLD, STOP_THRESHOLD
            
    except Exception as e:
        logger.error(f"Calibration failed: {e}")
        return START_THRESHOLD, STOP_THRESHOLD

def listen():
    """
    listen to default input device and perform an action if sound starts or stops
    """
    p = pyaudio.PyAudio()
    snd_started = False
    silent_periods = 0
    
    # Calibrate noise floor and set dynamic thresholds
    try:
        dynamic_start, dynamic_stop = calibrate_noise_floor(p)
        logger.info(f"Using dynamic thresholds - Start: {dynamic_start}, Stop: {dynamic_stop}")
    except Exception as e:
        logger.error(f"Error during calibration: {e}, using default thresholds")
        dynamic_start, dynamic_stop = START_THRESHOLD, STOP_THRESHOLD
    
    # Use a rolling window to smooth out audio level detection
    recent_levels = []
    
    while 1:
        try:
            # using default input -- needs to be dsnoop configured in alsa
            stream = p.open(format=FORMAT, channels=2, rate=RATE, input=True, output=False, frames_per_buffer=CHUNK_SIZE)
            # little endian, signed short - use exception_on_overflow=False to prevent errors
            snd_data = array('h', stream.read(CHUNK_SIZE, exception_on_overflow=False))
            if sys.byteorder == 'big':
                snd_data.byteswap()

            max_level = max(snd_data)
            
            # Keep track of recent audio levels for smoothing
            recent_levels.append(max_level)
            if len(recent_levels) > 5:  # Keep a window of 5 samples
                recent_levels.pop(0)
            avg_level = sum(recent_levels) / len(recent_levels)
            
            # If we detect audio above threshold
            if not snd_started:
                # Count samples above threshold in this chunk
                samples_above = count_samples_above_threshold(snd_data, dynamic_start)
                
                # If we have enough samples above threshold in a single chunk, start streaming
                if samples_above >= MIN_ACTIVE_SAMPLES:
                    logger.info(f"Starting stream. Volume level: {max_level}, samples above threshold: {samples_above}/{MIN_ACTIVE_SAMPLES}")
                    start = subprocess.run(["mpc", f"--host={hifipi_ip}","play"], capture_output=True, text=True)
                    
                    if start.stdout:
                        received_stream = start.stdout.splitlines()[0]
                        if received_stream != ls_stream:
                            logger.error(f"Unexpected stream response. Received: {received_stream}, expected: {ls_stream}. Command: {start.args}")
                        else:
                            logger.info(f"MPC output: {start.stdout.strip()}")
                            snd_started = True
                            silent_periods = 0
                    elif start.stderr:
                        logger.error(f"MPC play error. Full command result: {start}. Resetting playlist...")
                        # Reset the playlist
                        subprocess.run(["mpc", f"--host={hifipi_ip}","clear"], capture_output=True)
                        # Get current IP address
                        my_ip = socket.gethostbyname(socket.gethostname())
                        # Add stream back to playlist
                        add_result = subprocess.run(["mpc", f"--host={hifipi_ip}","add", f"http://{my_ip}:8000/phono.ogg"], capture_output=True, text=True)
                        if add_result.stderr:
                            logger.error(f"Failed to add stream back to playlist: {add_result.stderr}")
                        else:
                            # Try playing again
                            subprocess.run(["mpc", f"--host={hifipi_ip}","play"], capture_output=True)
                
            elif snd_started and is_silent(snd_data, dynamic_stop):
                silent_periods += 1
                # Only stop after multiple consecutive silent periods
                if silent_periods >= MIN_SILENT_PERIODS:
                    logger.info(f"Stopping stream. Volume level: {max_level}")
                    stop = subprocess.run(["mpc", f"--host={hifipi_ip}","stop"], capture_output=True, text=True)
                    if stop.stdout: 
                        logger.info(f"MPC output: {stop.stdout.strip()}")
                    if stop.stderr: 
                        logger.error(f"MPC error output: {stop.stderr.strip()}")
                    snd_started = False
                    silent_periods = 0
            else:
                # Reset silent period counter if we detect sound while stream is active
                if snd_started and not is_silent(snd_data, dynamic_stop):
                    silent_periods = 0
                # Reset active periods counter if we don't detect sound
                if is_silent(snd_data, dynamic_start):
                    active_periods = 0
                    
            stream.stop_stream()
            stream.close()
            
        except Exception as e:
            logger.error(f"Error in audio processing loop: {e}")
            time.sleep(1)  # Wait a bit before retrying after an error
            continue
            
        # Add a small sleep to reduce CPU usage
        time.sleep(0.1)


if __name__ == '__main__':
    # Start the listening loop
    listen()
