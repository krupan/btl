typedef class Transaction;

class ResponseTracker;
    // This is for INCOMPLETE_RSP transactions.  Each INCOMPLETE_RSP
    // txn may need multiple responses (e.g., if the request size is
    // larger than the allowed rsp size).  These are referred to as
    // sub responses (sub_rsp objects).  This is a queue so we know
    // the order of the data in the case of sub_rsp objects.
    Transaction incomplete_responses[$];

    ////////////////////////////////////////////////////////////////////////////
    // rsp methods
    ////////////////////////////////////////////////////////////////////////////

    // Adds INCOMPLETE_RSP to incomplete_responses list
    virtual function void add_incomplete_response(Transaction rsp);
        assert(rsp.base_type == INCOMPLETE_RSP);
        incomplete_responses.push_back(rsp);
    endfunction

    // Returns whether rsp matches an incomplete response in our list
    virtual function bit matches_incomplete_response(Transaction rsp);
        Value unused;
        return get_incomplete_response(rsp, unused);
    endfunction

    // Outputs the index of the incomplete response that matches the
    // passed in response.  Probably shouldn't be called except by
    // matches_incomplete_response and update_incomplete_rsp functions
    virtual function bit get_incomplete_response(Transaction rsp_in,
                                                 output Value index);
        int results[$];
        results = incomplete_responses.find_index(rsp)
            with (rsp.tag == rsp_in.tag);
        case(results.size())
            0: return 0;
            1: begin
                index = {32'h0, results[0]};
                assert(incomplete_responses[index[31:0]].data_size == rsp_in.data_size);
                return 1;
            end
            // there's a bug in the code if we get here
            default: assert(0);
        endcase
    endfunction

    // Updates the incomplete response that matches the passed in
    // response.  Changes type from INCOMPLETE_RSP to RSP, copies the
    // data from the passed in response to the (formerly) incomplete
    // response.  Assumes a matching response exists, which can be
    // verified by calling get_incomplete_response first.
    virtual function void update_incomplete_rsp(Transaction rsp);
        Value index;
        bit success = get_incomplete_response(rsp, index);
        assert(success);
        incomplete_responses[index].base_type = btl::RSP;
        incomplete_responses[index].data = rsp.data;
    endfunction

    virtual function void complete_incomplete_rsp(Transaction rsp);
        Value index;
        bit success = get_incomplete_response(rsp, index);
        assert(success);
        incomplete_responses.delete(index[31:0]);
    endfunction

    ////////////////////////////////////////////////////////////////////////////
    // sub response methods
    ////////////////////////////////////////////////////////////////////////////

    // Outputs the index of the incomplete response that is waiting
    // for the passed in sub response and returns 1.  If there is no
    // incomplete response waiting for the passed in sub response,
    // returns 0.
    virtual function bit get_incomplete_sub_rsp(Transaction sub_rsp,
                                                output Value index);
        int results[$];
        results = incomplete_responses.find_index(rsp)
            with (rsp.matches_incomplete_response(sub_rsp) == 1);
        assert(results.size() <= 1);
        if(results.size() == 0) begin
            return 0;
        end
        index = {32'h0, results[0]};
        return 1;
    endfunction

    // For the incomplete response at index, updates the incomplete
    // sub response that matches the passed in sub response.  See the
    // comment for update_incomplete_rsp for more details. Get the
    // index by calling get_incomplete_sub_rsp.
    virtual function void update_incomplete_sub_rsp(Value index,
                                                    Transaction sub_rsp);
        assert(index < {32'h0, incomplete_responses.size()});
        incomplete_responses[index].update_incomplete_rsp(sub_rsp);
    endfunction

    // Returns 1 if there are any incomplete sub responses for the
    // incomplete response at the given index.
    virtual function bit are_incomplete_sub_rsps(Value index);
        foreach(incomplete_responses[index].incomplete_responses[i]) begin
            if(incomplete_responses[index].incomplete_responses[i].base_type
                == btl::INCOMPLETE_RSP) begin
                    return 1;
                end
        end
        return 0;
    endfunction

    // Copies data from all incomplete sub responses to the incomplete
    // response at index.
    function void sub_rsps_complete(Value index);
        incomplete_responses[index].rsp_complete();
    endfunction

    function void end_of_test();
        assert(incomplete_responses.size() == 0);
    endfunction
endclass : ResponseTracker
