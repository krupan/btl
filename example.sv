// what I really need here is to start with a high-level transaction,
// have the HighToLow receive it, translate it into multiple low-level
// transactions with each requiring a response, and pass a mid-level
// transaction that indicates that to LowToHigh.  LowToHigh then waits
// to receive all the responses before producing a corresponding
// high-level transaction.

package tb;

    localparam MAX_LL_PAYLOAD_BYTES = 256;

    typedef enum {
        MEM_READ,
        MEM_WRITE,
        CPL
    } LowLevelTxnType;

    class TxnLowLevel extends btl::Transaction;
        LowLevelTxnType my_type;
        function new(btl::BaseTxnType type_in);
            super.new(type_in);
            name = "low level Txn";
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
                if(!$cast(txn_in, txn)) begin
                    continue;
                end
                $display("LowLevel got\n", txn_in.sprint());
                case(txn_in.base_type)
                    btl::READ_REQ, btl::WRITE_REQ: begin
                        $display("LowLevel sending response");
                        // simulating real hardware at this low level,
                        // so add a delay
                        #5;
                        txn_out = new(btl::RSP);
                        txn_out.name = "response from LowLevel";
                        txn_out.requester_id = txn_in.id;
                        for(int i = 0; i < txn_in.data_size; i++) begin
                            txn_out.data.push_back($urandom[7:0]);
                        end
                        foreach(subscribers[i]) begin
                            subscribers[i].put(txn_out);
                        end
                    end
                    default: begin
                        // ignoring others for now
                    end
                endcase
            end
        endtask
    endclass

    class LowToHigh implements btl::Component, btl::Subscriber, btl::Producer;
        btl::SubscriberList subscribers;
        btl::TxnMailbox txns_in;
        btl::Transaction txns_waiting_rsp[btl::ID];

        function void add_subscriber(btl::Subscriber subscriber);
            subscribers.push_back(subscriber);
        endfunction

        function new();
            txns_in = new();
        endfunction

        task put(btl::Transaction txn);
            txns_in.put(txn);
        endtask

        task handle_high_level(btl::Transaction txn);
            $display("LowToHigh TODO: handle high-level transactions");
        endtask

        task run();
            forever begin
                btl::Transaction txn;
                TxnLowLevel txn_in;
                btl::Transaction txn_out;
                txns_in.get(txn);
                if(!$cast(txn_in, txn)) begin
                    handle_high_level(txn);
                    continue;
                end
                $display("LowToHigh got\n", txn_in.sprint());
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

        task send_to_subscribers(btl::Transaction txn);
            foreach(subscribers[i]) begin
                subscribers[i].put(txn);
            end
        endtask

        task handle_req(btl::Transaction txn_in);
            // this is used to keep track of the low-level requests we
            // send out
            btl::Transaction expected_cpl;
            btl::Transaction txns_to_send[$];
            int unsigned data_to_request;
            if(txn_in.base_type == btl::READ_REQ) begin
                data_to_request = txn_in.data_size;
            end
            else begin
                data_to_request = txn_in.data.size();
            end
            expected_cpl = new(btl::INCOMPLETE_RSP);
            expected_cpl.requester_id = txn_in.id;
            expected_cpl.data_size = data_to_request;
            while(data_to_request > 0) begin
                TxnLowLevel txn_out = new(txn_in.base_type);
                TxnLowLevel rsp = new(btl::RSP);
                txn_out.name = "ll read request";

                txn_out.id = $urandom;
                rsp.requester_id = txn_out.id;

                txn_out.data_size = btl::min(data_to_request, MAX_LL_PAYLOAD_BYTES);
                rsp.data_size = txn_out.data_size;
                expected_cpl.missing_responses[txn_out.id] = rsp;
                data_to_request -= txn_out.data_size;
                if(txn_out.base_type == btl::WRITE_REQ) begin
                    for(int i = 0; i < txn_out.data_size; i++) begin
                        txn_out.data.push_back(txn_in.data.pop_front());
                    end
                end
                txns_to_send.push_back(txn_out);
            end
            // send this out for anyone interested in the completions
            // to the the original request
            send_to_subscribers(expected_cpl);
            foreach(txns_to_send[i]) begin
                send_to_subscribers(txns_to_send[i]);
            end
        endtask

        task handle_rsp(btl::Transaction txn_in);
            // convert to (multiple, if needed) low level response(s)
        endtask

        task run();
            forever begin
                btl::Transaction txn_in;
                txns_in.get(txn_in);
                $display("HighToLow got\n", txn_in.sprint());
                case(txn_in.base_type)
                    btl::READ_REQ, btl::WRITE_REQ: handle_req(txn_in);
                    btl::RSP: handle_rsp(txn_in);
                    default: assert(0);
                endcase
            end
        endtask
    endclass : HighToLow

    // TODO: Currently does not accept requests, fix that.
    class HighLevel implements btl::Component, btl::Subscriber, btl::Producer;
        btl::SubscriberList subscribers;
        btl::TxnMailbox txns_in;
        // Use requester IDs for the keys to this associative array
        btl::Transaction missing_responses[btl::ID];

        function void add_subscriber(btl::Subscriber subscriber);
            subscribers.push_back(subscriber);
        endfunction

        function new();
            txns_in = new();
        endfunction

        task put(btl::Transaction txn);
            txns_in.put(txn);
        endtask

        task write(longint unsigned addr, btl::ByteQ data);
            btl::Transaction req = new(btl::WRITE_REQ);
            btl::Transaction rsp = new(btl::INCOMPLETE_RSP);
            req.id = $urandom;
            req.name = "hl read request";
            req.data_size = data.size();
            foreach(subscribers[i]) begin
                subscribers[i].put(req);
            end
        endtask

        task read(longint unsigned addr,
                  int unsigned data_size,
                  output btl::ByteQ data);
            btl::Transaction req = new(btl::READ_REQ);
            btl::Transaction rsp = new(btl::INCOMPLETE_RSP);
            req.id = $urandom;
            rsp.requester_id = req.id;

            req.name = "hl read request";
            rsp.name = "hl response";

            req.data_size = data_size;
            rsp.data_size = data_size;

            missing_responses[req.id] = rsp;
            foreach(subscribers[i]) begin
                subscribers[i].put(req);
            end

            wait(rsp.base_type == btl::RSP);
            missing_responses.delete(req.id);
            data = rsp.data;
        endtask

        task run();
            forever begin
                btl::Transaction txn;
                txns_in.get(txn);
                $display("HighLevel got\n", txn.sprint());
                if(txn.base_type != btl::RSP) begin
                    continue;
                end
                if(missing_responses.exists(txn.requester_id) == 0) begin
                    continue;
                end
                assert(missing_responses[txn.requester_id].requester_id == txn.requester_id);
                missing_responses[txn.requester_id].data = txn.data;
                missing_responses[txn.requester_id].base_type = btl::RSP;
            end
        endtask
    endclass : HighLevel
endpackage : tb

module top;
    tb::LowLevel low_level;
    tb::LowToHigh low_to_high;
    tb::HighToLow high_to_low;
    tb::HighLevel high_level;
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
        repeat(10) begin
            automatic longint unsigned addr = {$urandom, $urandom};
            automatic int unsigned size = 1024;
            automatic btl::ByteQ read_data;
            $display("issuing read");
            high_level.read(addr, size, read_data);
            $display("read: %p", read_data);
        end
        $finish();
    end
endmodule
