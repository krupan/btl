// what I really need here is to start with a high-level transaction,
// have the HighToLow receive it, translate it into multiple low-level
// transactions with each requiring a response, and pass a mid-level
// transaction that indicates that to LowToHigh.  LowToHigh then waits
// to receive all the responses before producing a corresponding
// high-level transaction.

package tb;

    typedef enum {
        MEM_READ,
        MEM_WRITE,
        CPL
    } LowLevelTxnType;

    class ExampleTxnBase extends btl::Transaction;
        const int unsigned max_data_size;
        btl::Transaction outstanding_reqs[$];

        function new(btl::BaseTxnType type_in);
            super.new(type_in);
            name = "base Txn";
        endfunction
    endclass

    class TxnLowLevel extends ExampleTxnBase;
        LowLevelTxnType my_type;
        function new(btl::BaseTxnType type_in);
            super.new(type_in);
            name = "low level Txn";
            max_data_size = 256;
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
                txns_in.get(txn);
                $cast(txn_in, txn);
                $display("LowLevel got txn: ", txn_in.sprint());
                if(txn_in.base_type == btl::REQ) begin
                    $display("LowLevel sending response");
                    txn_out = new(btl::RSP);
                    txn_out.name = "response from LowLevel";
                    txn_out.requester_id = txn_in.id;
                    for(int i = 0; i < txn_in.requested_data_size; i++) begin
                        txn_out.data.push_back($urandom[7:0]);
                    end
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
                txn_out = new(txn_in.base_type);
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
                txn_out = new(txn_in.base_type);
                txn_out.name = "from HighToLow";
                txn_out.id = txn_in.id;
                foreach(subscribers[i]) begin
                    subscribers[i].put(txn_out);
                end
            end
        endtask
    endclass

    class HighLevel implements btl::Component, btl::Subscriber, btl::Producer;
        btl::SubscriberList subscribers;
        btl::TxnMailbox txns_in;
        btl::Transaction txns_waiting_rsp[ID];

        function void add_subscriber(btl::Subscriber subscriber);
            subscribers.push_back(subscriber);
        endfunction

        function new();
            txns_in = new();
        endfunction

        task put(btl::Transaction txn);
            txns_in.put(txn);
        endtask

        task publish(btl::Transaction);
            foreach(subscribers[i]) begin
                subscribers[i].put(txn_out);
            end
        endtask

        task write(longint unsigned addr, btl::ByteQ data);
            btl::Transaction txn = new(btl::READ);
            txn.id = $urandom;
            txn.name = "hl write request";
            txn.data = data;
            publish(txn);
        endtask

        task read(longint unsigned addr,
                  int unsigned data_size,
                  output btl::ByteQ data);
            btl::Transaction req = new(btl::READ);
            btl::Transaction rsp = new(btl::WAITING_RSP);
            req.id = $urandom;
            rsp.requester_id = req.id;
            req.name = "hl read request";
            rsp.name = "hl response";
            req.requested_data_size = data_size;
            rsp.requested_data_size = data_size;
            txns_waiting_rsp[req.id] = rsp;
            publish(req);
            wait(rsp.base_type == RSP);
            txns_waiting_rsp.remove(req.id);
            data = rsp.data;
        endtask

        task run();
            forever begin
                btl::Transaction txn;
                txns_in.get(txn);
                $display("HighLevel got txn: ", txn.sprint());
                if(txn.base_type != RSP) begin
                    continue;
                end
                if(txns_waiting_rsp.exists(txn.id) == 0) begin
                    continue;
                end
                assert(txns_waiting_rsp[txn.id].base_type == WAITING_RSP);
                txns_waiting_rsp[txn.id].data = txn.data;
                txns_waiting_rsp[txn.id].base_type = RSP;
            end
        endtask
    endclass
endpackage : tb

module top;
    tb::LowLevel ll;
    tb::LowToHigh low_to_high;
    tb::HighToLow high_to_low;
    tb::HighLevel hl;
    initial begin;
        $display("test start");
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
            longint unsigned addr = $urandom;
            int unsigned size = 1024;
            hl.read(addr, size);
            txn_hl = new(btl::READ_REQ);
            txn_hl.requested_data_size = 1024;
            txn_bl.name = "request from tb top";
            $display("putting transaction");
            hl.put(txn_hl);
            #3;
        end
        #300;
        $finish();
    end
endmodule
