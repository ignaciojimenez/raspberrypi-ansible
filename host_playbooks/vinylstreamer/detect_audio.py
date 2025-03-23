from array import array
import pyaudio
import subprocess
import sys
import logging
import time
import socket

log_file="/home/choco/.log/detect_audio.log"

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(log_file)
    ]
)

START_THRESHOLD = 150
STOP_THRESHOLD = 50
CHUNK_SIZE = 2048
FORMAT = pyaudio.paInt16
RATE = 48000
# TODO pass these as args
hifipi_ip="10.30.40.100"
ls_stream="Turntable_stream"

def is_silent(snd_data, threshold):
    """
    Returns 'True' if below the 'silent' threshold"
    :param snd_data:
    :return: True|False
    """
    return max(snd_data) < threshold


def listen():
    """
    listen to default input device and perform an action if sound starts or stops
    """
    p = pyaudio.PyAudio()
    snd_started = False
    while 1:
        # using default input -- needs to be dsnoop configured in alsa
        stream = p.open(format=FORMAT, channels=2, rate=RATE, input=True, output=False, frames_per_buffer=CHUNK_SIZE)
        # little endian, signed short
        snd_data = array('h', stream.read(CHUNK_SIZE))
        if sys.byteorder == 'big':
            snd_data.byteswap()

        # Uncomment for debug level noise monitoring
        # logging.debug(f"Current Noise data: {max(snd_data)}")

        if (not snd_started) and (not is_silent(snd_data, START_THRESHOLD)):
            logging.info(f"Starting stream. Volume level: {max(snd_data)}")
            start = subprocess.run(["mpc", f"--host={hifipi_ip}","play"], capture_output=True, text=True)
            if start.stdout:
                received_stream = start.stdout.splitlines()[0]
                if received_stream != ls_stream:
                    logging.error(f"Unexpected stream response. Received: {received_stream}, expected: {ls_stream}. Command: {start.args}")
                else:
                    logging.info(f"MPC output: {start.stdout.strip()}")
                    snd_started = True
            elif start.stderr:
                logging.error(f"MPC play error. Full command result: {start}. Resetting playlist...")
                # Reset the playlist
                subprocess.run(["mpc", f"--host={hifipi_ip}","clear"], capture_output=True)
                # Get current IP address
                import socket
                my_ip = socket.gethostbyname(socket.gethostname())
                # Add stream back to playlist
                add_result = subprocess.run(["mpc", f"--host={hifipi_ip}","add", f"http://{my_ip}:8000/phono.ogg"], capture_output=True, text=True)
                if add_result.stderr:
                    logging.error(f"Failed to add stream back to playlist: {add_result.stderr}")
                else:
                    # Try playing again
                    subprocess.run(["mpc", f"--host={hifipi_ip}","play"], capture_output=True)
        elif snd_started and is_silent(snd_data, STOP_THRESHOLD):
            logging.info(f"Stopping stream. Volume level: {max(snd_data)}")
            stop = subprocess.run(["mpc", f"--host={hifipi_ip}","stop"], capture_output=True, text=True)
            if stop.stdout: logging.info(f"MPC output: {stop.stdout.strip()}")
            if stop.stderr: logging.error(f"MPC error output: {stop.stderr.strip()}")
            snd_started = False

        stream.stop_stream()
        stream.close()


if __name__ == '__main__':
    listen()
