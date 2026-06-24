package tb;

    class ExampleTxnBase implements btl::Transaction;
        string my_type;
        string name;
        int id;
        function new();
            name = "txn base";
            id = $urandom;
        endfunction

        function string sprint();
            return $sformatf("id: 0x%0x, type: %s", id, my_type);
        endfunction
    endclass

    class TxnLowLevel extends ExampleTxnBase;
        function new();
            super.new();
            my_type = "low level";
        endfunction
    endclass

    class TxnMidLevel extends ExampleTxnBase;
        function new();
            super.new();
            my_type = "mid level";
        endfunction
    endclass

    class TxnHighLevel extends ExampleTxnBase;
        function new();
            super.new();
            my_type = "high level";
        endfunction
    endclass

    // Produces and Consumes TxnLowLevel
    class LowLevel implements btl::Component, btl::Subscriber, btl::Producer;
        btl::SubscriberList subscribers;
        btl::TxnMailbox txns_in;

        function void add_subscriber(btl::Subscriber subscriber);
            subscribers.push_back(subscriber);
        endfunction

        function new();
            txns_in = new();
        endfunction

        task put(btl::Transaction txn);
            txns_in.put(txn);
        endtask

        task run();
            forever begin
                btl::Transaction txn;
                TxnLowLevel txn_in;
                TxnLowLevel txn_out;
                // #1;
                txns_in.get(txn);
                $cast(txn_in, txn);
                $display("LowLevel got txn: ", txn_in.sprint());
                if(txn_in.name == "from tb top") begin
                    txn_out = new();
                    txn_out.name = "from LowLevel";
                    txn_out.id = txn_in.id;
                    foreach(subscribers[i]) begin
                        subscribers[i].put(txn_out);
                    end
                end
            end
        endtask
    endclass

    class LowToHigh implements btl::Component, btl::Subscriber, btl::Producer;
        btl::SubscriberList subscribers;
        btl::TxnMailbox txns_in;

        function void add_subscriber(btl::Subscriber subscriber);
            subscribers.push_back(subscriber);
        endfunction

        function new();
            txns_in = new();
        endfunction

        task put(btl::Transaction txn);
            txns_in.put(txn);
        endtask

        task run();
            forever begin
                btl::Transaction txn;
                TxnLowLevel txn_in;
                TxnHighLevel txn_out;
                // #1;
                txns_in.get(txn);
                $cast(txn_in, txn);
                $display("LowToHigh got txn: ", txn_in.sprint());
                txn_out = new();
                txn_out.name = "from LowToHigh";
                txn_out.id = txn_in.id;
                foreach(subscribers[i]) begin
                    subscribers[i].put(txn_out);
                end
            end
        endtask
    endclass

    class HighToLow implements btl::Component, btl::Subscriber, btl::Producer;
        btl::SubscriberList subscribers;
        btl::TxnMailbox txns_in;

        function void add_subscriber(btl::Subscriber subscriber);
            subscribers.push_back(subscriber);
        endfunction

        function new();
            txns_in = new();
        endfunction

        task put(btl::Transaction txn);
            txns_in.put(txn);
        endtask

        task run();
            forever begin
                btl::Transaction txn;
                TxnHighLevel txn_in;
                TxnLowLevel txn_out;
                // #1;
                txns_in.get(txn);
                $cast(txn_in, txn);
                $display("HighToLow got txn: ", txn_in.sprint());
                txn_out = new();
                txn_out.name = "from HighToLow";
                txn_out.id = txn_in.id;
                foreach(subscribers[i]) begin
                    subscribers[i].put(txn_out);
                end
            end
        endtask
    endclass

    // Produces and Consumes TxnHighLevel
    class HighLevel implements btl::Component, btl::Subscriber, btl::Producer;
        btl::SubscriberList subscribers;
        btl::TxnMailbox txns_in;

        function void add_subscriber(btl::Subscriber subscriber);
            subscribers.push_back(subscriber);
        endfunction

        function new();
            txns_in = new();
        endfunction

        task put(btl::Transaction txn);
            txns_in.put(txn);
        endtask

        task run();
            forever begin
                btl::Transaction txn;
                TxnHighLevel txn_in;
                TxnHighLevel txn_out;
                // #1;
                txns_in.get(txn);
                $cast(txn_in, txn);
                $display("HighLevel got txn: ", txn_in.sprint());
                txn_out = new();
                txn_out.name = "from HighLevel";
                txn_out.id = txn_in.id;
                foreach(subscribers[i]) begin
                    subscribers[i].put(txn_out);
                end
            end
        endtask
    endclass
endpackage : tb

module top;
    tb::LowLevel ll;
    tb::LowToHigh low_to_high;
    tb::HighToLow high_to_low;
    tb::HighLevel hl;
    tb::TxnLowLevel txn_ll;
    initial begin;
        $display("test start");
        txn_ll = new();
        ll = new();
        low_to_high = new();
        high_to_low = new();
        hl = new();

        ll.add_subscriber(low_to_high);
        low_to_high.add_subscriber(hl);

        hl.add_subscriber(high_to_low);
        high_to_low.add_subscriber(ll);
        $display("forking processes");
        fork
            low_to_high.run();
            high_to_low.run();
            hl.run();
            ll.run();
        join_none
        repeat(10) begin
            txn_ll = new();
            txn_ll.name = "from tb top";
            $display("putting transaction");
            ll.put(txn_ll);
            #3;
        end
        #300;
        $finish();
    end
endmodule
