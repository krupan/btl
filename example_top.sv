module example_top;
    tb::LowLevel low_level;
    tb::LowToHigh low_to_high;
    tb::HighToLow high_to_low;
    tb::HighLevel high_level;
    btl::ByteQ test_data[longint unsigned];
    example_regs::ExampleRegs target_regs;
    longint unsigned addr;
    longint unsigned value;
    btl::ByteQ data;
    btl_regs::Reg csr;
    btl_regs::Field csr_field;
    bit success;

    initial begin;
        $display("test start");
        low_level = new();
        low_to_high = new();
        high_to_low = new();
        high_level = new();
        target_regs = new();

        low_level.add_subscriber(low_to_high);
        low_to_high.add_subscriber(high_level);
        low_to_high.add_subscriber(high_to_low);

        high_level.add_subscriber(high_to_low);
        high_to_low.add_subscriber(low_level);
        high_to_low.add_subscriber(low_to_high);

        $display("forking processes");
        fork
            low_to_high.run();
            high_to_low.run();
            high_level.run();
            low_level.run();
        join_none

        // write/read registers
        success = target_regs.reg_by_name("csr_a", csr);
        assert(success);
        high_level.read(csr.offset, csr.size_bytes, data);
        value = btl::byteq_to_value(data);
        $display("reg_value: 0x%x", value);
        csr.write(value);
        foreach(csr.fields[i]) begin
            if(csr.fields[i].reset_value != csr.fields[i].value) begin
                $display("expected field %s value: 0x%0x does not match read value: 0x%0x",
                         csr.fields[i].name,
                         csr.fields[i].reset_value,
                         csr.fields[i].value);
                assert(0);
            end
            else begin
                $display("expected field %s value: 0x%0x matches read value: 0x%0x",
                         csr.fields[i].name,
                         csr.fields[i].reset_value,
                         csr.fields[i].value);
            end
        end
        
        // show that we modified the register inside target_regs
        // AddrMap through the csr reference
        success = target_regs.reg_read(csr.offset, value);
        assert(success);
        assert(csr.read() == value);

        // change a field, write the new register value
        success = csr.field_by_name("message", csr_field);
        assert(success);
        csr_field.write('hfeed33);
        data = btl::value_to_byteq(csr.read());
        high_level.write(csr.offset, data);
        data.delete();
        high_level.read(csr.offset, csr.size_bytes, data);
        value = btl::byteq_to_value(data);
        assert(value == csr.read());
        
        // writes some data
        // repeat(10) begin
        //     automatic int unsigned size = $urandom_range(255, 1024);
        //     addr = {$urandom, $urandom};
        //     $display("issuing write");
        //     data.delete();
        //     for(int i = 0; i < size; i++) begin
        //         data.push_back($urandom[7:0]);
        //     end
        //     high_level.write(addr, data);
        //     test_data[addr] = data;
        // end
        
        // // read data back
        // foreach(test_data[i]) begin
        //     $display("issuing read");
        //     data.delete();
        //     high_level.read(i, test_data[i].size(), data);
        //     if(data.size() != test_data[i].size()) begin
        //        $error("read_data.size: %0d, test_data[i].size: %0d",
        //               data.size, test_data[i].size);
        //     end
        //     foreach(data[j]) begin
        //         if(data[j] != test_data[i][j]) begin
        //             $error("read_data[%0d], 0x%0x, does not match test_data[0x%0x][%0d], 0x%0x",
        //                    j, data[j], i, j, test_data[i][j]);
        //         end
        //     end
        //     if(data != test_data[i]) begin
        //         // TODO: explain more about why it failed.  Size?  One or more bytes wrong?  Which bytes?
        //         $error("read of addr 0x%0x failed!", i);
        //         continue;
        //     end
        //     $display("read success!");
        // end
        low_level.end_of_test();
    low_to_high.end_of_test();
high_to_low.end_of_test();
high_level.end_of_test();
$finish();
end
endmodule
