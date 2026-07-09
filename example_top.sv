module example_top;
    tb::LowLevel low_level;
    tb::LowToHigh low_to_high;
    tb::HighToLow high_to_low;
    tb::HighLevel high_level;
    btl::ByteQ test_data[longint unsigned];
    // this provides us with name/address mapping, easy register field
    // parsing/assignment, and a place to record expected values.
    example_regs::ExampleRegs shadow_regs;
    longint unsigned addr;
    longint unsigned value;
    btl_regs::Reg csr;
    btl_regs::Field csr_field;

    initial begin : test;
        $display("test start");
        low_level = new();
        low_to_high = new();
        high_to_low = new();
        high_level = new();
        shadow_regs = new(0, 8);

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
        $display("checking csr_a reset value");
        shadow_regs.reg_by_name("csr_a", csr);
        high_level.read_reg(csr.offset, csr.size_bytes, value);
        $display("read: 0x%0x from csr_a", value);

        // record the value we just read
        csr.write(value);

        // check that read value matches reset value for each field
        foreach(csr.fields[i]) begin
            if(csr.fields[i].reset_value != csr.fields[i].value) begin
                $display("FAIL");
                $display("  expected field %s value: 0x%0x does not match read value: 0x%0x",
                         csr.fields[i].name,
                         csr.fields[i].reset_value,
                         csr.fields[i].value);
                assert(0);
            end
            else begin
                $display("Success!");
                $display("  expected field %s value: 0x%0x matches read value: 0x%0x",
                         csr.fields[i].name,
                         csr.fields[i].reset_value,
                         csr.fields[i].value);
            end
        end

        // show that we can modify the register inside the shadow_regs
        // AddrMap through the csr reference we obtained above
        csr.write(64'hffffffff);
        value = shadow_regs.reg_read(csr.offset);
        // expected value due to read-only fields:
        assert(64'hffffff07 == value);

        // get back to the value we read before this little test
        csr.reset();

        $display("writing csr_a message field and reading back");
        // change a field, write the new register value
        csr.field_by_name("message", csr_field);
        // this modifies just the message field (3 bytes) in our
        // shadow_regs csr_a register
        $display("shadow csr_a is: 0x%0x", csr.read());
        csr_field.write('hfeed33);
        // csr.read() gives us the full csr_a value after modifying
        // the message field
        $display("shadow csr_a is now: 0x%0x", csr.read());
        // write the actual csr_a register
        high_level.write_reg(csr.offset, csr.size_bytes, csr.read());
        // read csr_a back
        high_level.read_reg(csr.offset, csr.size_bytes, value);
        // check the data we read with what's stored in shadow_regs
        if(value != csr.read()) begin
            $display("expected: 0x%0x, got: 0x%0x",
                     csr.read(), value);
            assert(0);
        end

        // writes some data
        repeat(10) begin
            btl::ByteQ data;
            automatic int unsigned size = $urandom_range(255, 1024);
            addr = {$urandom, $urandom};
            $display("issuing write");
            data.delete();
            for(int i = 0; i < size; i++) begin
                data.push_back($urandom[7:0]);
            end
            high_level.write(addr, data);
            test_data[addr] = data;
        end

        // read data back
        foreach(test_data[i]) begin
            btl::ByteQ data;
            $display("issuing read");
            data.delete();
            high_level.read(i, test_data[i].size(), data);
            if(data.size() != test_data[i].size()) begin
                $error("read_data.size: %0d, test_data[i].size: %0d",
                       data.size, test_data[i].size);
            end
            foreach(data[j]) begin
                if(data[j] != test_data[i][j]) begin
                    $error("read_data[%0d], 0x%0x, does not match test_data[0x%0x][%0d], 0x%0x",
                           j, data[j], i, j, test_data[i][j]);
                end
            end
            if(data != test_data[i]) begin
                // TODO: explain more about why it failed.  Size?  One or more bytes wrong?  Which bytes?
                $error("read of addr 0x%0x failed!", i);
                continue;
            end
            $display("read success!");
        end
        low_level.end_of_test();
        low_to_high.end_of_test();
        high_to_low.end_of_test();
        high_level.end_of_test();
        $finish();
    end : test
endmodule
