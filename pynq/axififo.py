from pynq import DefaultIP

class AxiStreamFifoDriver(DefaultIP):
    # This line is always the same for any driver
    def __init__(self, description):
        # This line is always the same for any driver
        super().__init__(description=description)
        self._reg_map = self.register_map
    
    bindto = ['xilinx.com:ip:axi_fifo_mm_s:4.2']
    
    def read_num_tx_room(self):
        """
        Reads the number of 32-bit words that the TX FIFO has room for
        """
        return self.read(self._reg_map.TDFV.address)
    
    def send_tx_pkt(self, data, wait_for_room=True):
        """
        Sends a list of integers (32-bit words) into the TX FIFO.
        If wait_for_room is True this will wait until there is room.
        """
        num_tx = len(data)
        if type(data) is bytes :
            num_tx >>= 2  # floors non 4 byte len

        if wait_for_room == True :
            while num_tx > self.read_num_tx_room() :
                pass

        # Writing a zero to hardware might be bad
        if num_tx != 0 :
            if type(data) is bytes :
                self.write(self._reg_map.TDFD.address, data)
            else :
                for i in data:
                    self.write(self._reg_map.TDFD.address, i)
            # This FIFO reg counts bytes
            self.write(self._reg_map.TLR.address, num_tx << 2)
   
    def read_num_rx_words(self):
        """
        Reads the number of 32-bit words in the RX FIFO yet to be read out
        """
        return self.read(self._reg_map.RDFO.address)
    
    def get_rx_fifo_pkt(self):
        """
        Pulls a single packet of data out of the RX FIFO.
        If there is no data to read, return an empty list
        """
        if (self.read(self._reg_map.RDFO.address) == 0):
            return []
        out_data = []
        num_rx_words = self.read(self._reg_map.RLR.address) >> 2  # Read number of words in packet
        for _ in range(num_rx_words):  # Read entire packet of data out
            out_data.append(self.read(self._reg_map.RDFD.address))
        return out_data