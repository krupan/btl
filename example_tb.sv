package tb;

    localparam MAX_LL_PAYLOAD_BYTES = 256;

    typedef enum {
        MEM_READ,
        MEM_WRITE,
        CPL
    } LowLevelTxnType;

    class TxnLowLevel extends btl::Transaction;
        LowLevelTxnType sub_type;

        function new(btl::BaseTxnType type_in);
            super.new(type_in);
        endfunction

        function string sub_type_str();
            case(sub_type)
                MEM_READ: return "MEM_READ";
                MEM_WRITE: return "MEM_WRITE";
                CPL: return "CPL";
                default: assert(0);
            endcase
        endfunction

        virtual function string sprint_body();
            string str = {"sub_type: ", sub_type_str, "\n"};
            str = {str, super.sprint_body()};
            return str;
        endfunction
    endclass

    // Consumes and Produces TxnLowLevel objects
    class LowLevel extends btl::Component;
        // memory model very specific to this simple example
        // testbench, associative array of ByteQ's, indexed by address
        btl::ByteQ memory[longint unsigned];

        task handle_write(TxnLowLevel req);
            btl::ByteQ data;
            // simulating real hardware at this low level, so add a
            // delay
            #5;
            for(int i = 0; i < req.data_size; i++) begin
                byte unsigned data_byte = req.data.pop_front();
                data.push_back(data_byte);
            end
            memory[req.address] = data;
        endtask

        task handle_read(TxnLowLevel req);
            TxnLowLevel rsp;
            // simulating real hardware at this low level, so add a
            // delay
            #5;
            rsp = new(btl::RSP);
            rsp.sub_type = CPL;
            rsp.origin = "LowLevel";
            rsp.requester_id = req.id;
            assert(memory.exists(req.address) != 0);
            for(int i = 0; i < req.data_size; i++) begin
                rsp.data[i] = memory[req.address][i];
                rsp.data_size++;
            end
            $display({"\nLowLevel sending response:\n", rsp.sprint()});
            send_to_subscribers(rsp);
        endtask

        task handle_req(TxnLowLevel req);
            case(req.sub_type)
                MEM_READ: handle_read(req);
                MEM_WRITE: handle_write(req);
                default: assert(0);
            endcase
        endtask
        
        task handle_rsp(TxnLowLevel rsp);
            $display("LowLevel handle_rsp not implemented");
        endtask

        task run();
            forever begin
                btl::Transaction txn_in;
                TxnLowLevel ll_txn_in;
                txns_in.get(txn_in);
                if(!$cast(ll_txn_in, txn_in)) begin
                    // we only deal with TxnLowLevel objects
                    continue;
                end
                $display("\nLowLevel got:\n", ll_txn_in.sprint());
                case(ll_txn_in.base_type)
                    btl::READ_REQ, btl::WRITE_REQ: begin
                        handle_req(ll_txn_in);
                    end
                    btl::RSP: begin
                        handle_rsp(ll_txn_in);
                    end
                endcase
            end
        endtask
    endclass : LowLevel

    // converts TxnLowLevel objects to high-level Transaction objects
    class LowToHigh extends btl::Component;

        task handle_incomplete_rsp(btl::Transaction rsp);
            add_missing_response(rsp);
        endtask

        task handle_rsp(TxnLowLevel rsp_in);
            // find corresponding INCOMPLETE_RSP
            int unsigned index;
            bit success;
            success = get_missing_sub_rsp(rsp_in, index);
            if(!success) begin
                return; 
            end
            update_missing_sub_rsp(index, rsp_in);
            if(is_missing_sub_rsps(index)) begin
                // still missing responses
                return;
            end
            // if we got here, we've gotten all the missing low-level
            // responses that this high-level response needs
            sub_rsps_complete(index);
            missing_responses[index].origin = "LowToHigh";
            send_to_subscribers(missing_responses[index]);
            complete_missing_rsp(missing_responses[index]);
        endtask

        task handle_write(TxnLowLevel req);
            $display("LowToHigh handle_write not implemented");
        endtask

        task handle_read(TxnLowLevel req);
            $display("LowToHigh handle_read not implemented");
        endtask

        task handle_req(TxnLowLevel req);
            $display("LowToHigh handle_req not implemented");
        endtask

        task run();
            forever begin
                btl::Transaction txn_in;
                TxnLowLevel ll_txn_in;
                txns_in.get(txn_in);
                // possibilities:
                //
                // - ll txn from HighToLow - ignore
                // - ll txn from LowLevel - process
                // - hl txn from HightToLow - ignore unless INCOMPLETE_RSP
                if($cast(ll_txn_in, txn_in)) begin
                    if(ll_txn_in.origin == "HighToLow") begin
                        continue;
                    end
                    if(ll_txn_in.base_type == btl::RSP) begin
                        $display("\nLowToHigh got:\n", txn_in.sprint());
                        handle_rsp(ll_txn_in);
                        continue;
                    end
                    handle_req(ll_txn_in);
                    continue;
                end
                // handle hl txns
                if(txn_in.base_type != btl::INCOMPLETE_RSP) begin
                    continue;
                end
                $display("\nLowToHigh got:\n", txn_in.sprint());
                handle_incomplete_rsp(txn_in);
                continue;
            end
        endtask
    endclass : LowToHigh

    // converts high-level Transaction objects to TxnLowLevel objects
    class HighToLow extends btl::Component;

        task handle_incomplete_rsp(btl::Transaction rsp);
            $display("HighToLow: handle_incomplete_rsp not implemented");
        endtask

        task handle_rsp(btl::Transaction rsp);
            $display("HighToLow: handle_rsp not implemented");
        endtask

        task handle_write(btl::Transaction req);
            int unsigned data_count;
            int unsigned previous_data_count;
            data_count = req.data_size;
            previous_data_count = 0;
            while(data_count > 0) begin
                TxnLowLevel ll_req = new(req.base_type);
                ll_req.sub_type = MEM_WRITE;
                ll_req.origin = "HighToLow";
                ll_req.id = $urandom;
                /* verilator lint_off WIDTHEXPAND */
                ll_req.address = req.address + previous_data_count;
                ll_req.data_size = btl::min(data_count, MAX_LL_PAYLOAD_BYTES);
                previous_data_count = ll_req.data_size;
                for(int i = 0; i < ll_req.data_size; i++) begin
                    ll_req.data.push_back(req.data.pop_front());
                end
                data_count -= ll_req.data_size;
                send_to_subscribers(ll_req);
            end
        endtask

        task handle_read(btl::Transaction req);
            // this is used to keep track of the low-level requests we
            // send out
            btl::Transaction incomplete_rsp = new(btl::INCOMPLETE_RSP);
            btl::Transaction reqs_to_send[$];
            int unsigned data_count;
            int unsigned previous_data_count;
            data_count = req.data_size;
            previous_data_count = 0;
            incomplete_rsp.origin = "HighToLow";
            incomplete_rsp.requester_id = req.id;
            incomplete_rsp.data_size = data_count;
            while(data_count > 0) begin
                TxnLowLevel ll_req = new(req.base_type);
                TxnLowLevel expected_cpl = new(btl::INCOMPLETE_RSP);
                ll_req.sub_type = MEM_READ;
                ll_req.origin = "HighToLow";
                ll_req.id = $urandom;
                ll_req.address = req.address + previous_data_count;
                ll_req.data_size = btl::min(data_count, MAX_LL_PAYLOAD_BYTES);
                previous_data_count = ll_req.data_size;

                expected_cpl.sub_type = CPL;
                expected_cpl.requester_id = ll_req.id;
                expected_cpl.data_size = ll_req.data_size;
                incomplete_rsp.add_missing_response(expected_cpl);

                if(ll_req.base_type == btl::WRITE_REQ) begin
                    for(int i = 0; i < ll_req.data_size; i++) begin
                        ll_req.data.push_back(req.data.pop_front());
                    end
                end
                data_count -= ll_req.data_size;
                reqs_to_send.push_back(ll_req);
            end
            // send this out for anyone interested in the completions
            // to the the original request
            send_to_subscribers(incomplete_rsp);
            // send out all the ll requests
            foreach(reqs_to_send[i]) begin
                send_to_subscribers(reqs_to_send[i]);
            end
        endtask

        task handle_req(btl::Transaction req);
            case(req.base_type)
                btl::READ_REQ: handle_read(req);
                btl::WRITE_REQ: handle_write(req);
                default: assert(0);
            endcase
        endtask

        task run();
            forever begin
                btl::Transaction txn_in;
                TxnLowLevel ll_txn_in;
                txns_in.get(txn_in);
                // possibilities:
                //
                // - ll txn from LowToHigh - ignore
                // - hl txn from HighLevel - process
                // - hl txn from LowToHigh - ignore unless INCOMPLETE_RSP
                if($cast(ll_txn_in, txn_in)) begin
                    $display("\nHighToLow ignoring ll txn");
                    continue;
                end
                // handle hl txns
                if(txn_in.origin == "LowToHigh") begin
                    if(txn_in.base_type == btl::INCOMPLETE_RSP) begin
                        $display("\nHighToLow got:\n", txn_in.sprint());
                        handle_incomplete_rsp(txn_in);
                        continue;
                    end
                    // ignore all other types from LowToHigh
                    continue;
                end
                $display("\nHighToLow got:\n", txn_in.sprint());
                case(txn_in.base_type)
                    btl::RSP: handle_rsp(txn_in);
                    btl::READ_REQ, btl::WRITE_REQ: handle_req(txn_in);
                    default: assert(0);
                endcase
            end
        endtask
    endclass : HighToLow

    class HighLevel extends btl::Component;

        task write(longint unsigned addr, btl::ByteQ data);
            btl::Transaction req = new(btl::WRITE_REQ);
            req.id = $urandom;
            req.origin = "HighLevel";
            req.address = addr;
            req.data_size = data.size();
            req.data = data;
            send_to_subscribers(req);
        endtask

        task read(longint unsigned addr,
                  int unsigned data_size,
                  output btl::ByteQ data);
            btl::Transaction req = new(btl::READ_REQ);
            btl::Transaction rsp = new(btl::INCOMPLETE_RSP);

            req.id = $urandom;
            req.origin = "HighLevel";
            req.address = addr;
            req.data_size = data_size;

            rsp.requester_id = req.id;
            rsp.origin = "HighLevel";
            rsp.data_size = data_size;
            add_missing_response(rsp);

            send_to_subscribers(req);
            wait(rsp.base_type == btl::RSP);
            data = rsp.data;
            complete_missing_rsp(rsp);
        endtask

        task run();
            forever begin
                int unused;
                btl::Transaction txn_in;
                txns_in.get(txn_in);
                $display("\nHighLevel got:\n", txn_in.sprint());
                if(txn_in.base_type != btl::RSP) begin
                    continue;
                end
                if(!is_missing_response(txn_in)) begin
                    continue;
                end
                update_missing_rsp(txn_in);
            end
        endtask
    endclass : HighLevel
endpackage : tb
