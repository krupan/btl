module example_top;
    tb::LowLevel low_level;
    tb::LowToHigh low_to_high;
    tb::HighToLow high_to_low;
    tb::HighLevel high_level;
    btl::ByteQ data[longint unsigned];

    initial begin;
        $display("test start");
        low_level = new();
        low_to_high = new();
        high_to_low = new();
        high_level = new();

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
        // writes some data
        repeat(10) begin
            automatic longint unsigned addr = {$urandom, $urandom};
            automatic int unsigned size = $urandom_range(255, 1024);
            automatic btl::ByteQ write_data;
            $display("issuing write");
            for(int i = 0; i < size; i++) begin
                write_data.push_back($urandom[7:0]);
            end
            high_level.write(addr, write_data);
            data[addr] = write_data;
        end
        
        // read data back
        foreach(data[i]) begin
            automatic btl::ByteQ read_data;
            $display("issuing read");
            high_level.read(i, data[i].size(), read_data);
            if(read_data.size() != data[i].size()) begin
               $error("read_data.size: %0d, data[i].size: %0d",
                      read_data.size, data[i].size);
            end
            foreach(read_data[j]) begin
                if(read_data[j] != data[i][j]) begin
                    $error("read_data[%0d], 0x%0x, does not match data[0x%0x][%0d], 0x%0x",
                           j, read_data[j], i, j, data[i][j]);
                end
            end
            if(read_data != data[i]) begin
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
    end
endmodule
