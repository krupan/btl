typedef class Transaction;

class ResponseTracker;
    // This is for INCOMPLETE_RSP transactions.  Each INCOMPLETE_RSP
    // txn may need multiple responses (e.g., if the request size is
    // larger than the allowed rsp size).  These are referred to as
    // sub responses (sub_rsp objects).  This is a queue so we know
    // the order of the data in the case of sub_rsp objects.
    Transaction missing_responses[$];

    ////////////////////////////////////////////////////////////////////////////
    // rsp methods
    ////////////////////////////////////////////////////////////////////////////

    // Adds INCOMPLETE_RSP to missing_responses list
    virtual function void add_missing_response(Transaction rsp);
        assert(rsp.base_type == INCOMPLETE_RSP);
        missing_responses.push_back(rsp);
    endfunction

    // Returns whether rsp matches a missing response in our list
    virtual function bit is_missing_response(Transaction rsp);
        int unused;
        return get_missing_response(rsp, unused);
    endfunction

    // Outputs the index of the missing response that matches the
    // passed in response.  Probably shouldn't be called except by
    // is_missing_response and update_missing_rsp functions
    virtual function bit get_missing_response(Transaction rsp_in,
                                              output int index);
        int results[$];
        results = missing_responses.find_index(rsp)
            with (rsp.requester_id == rsp_in.requester_id);
        case(results.size())
            0: return 0;
            1: begin
                index = results[0];
                assert(missing_responses[index].data_size == rsp_in.data_size);
                return 1;
            end
            // there's a bug in the code if we get here
            default: assert(0);
        endcase
    endfunction

    // Updates the missing response that matches the passed in
    // response from INCOMPLETE_RSP to RSP, copying the data from the
    // passed in response to the missing response.  Assumes a matching
    // response exists, which can be verified by calling
    // get_missing_response first.
    virtual function void update_missing_rsp(Transaction rsp);
        int index;
        bit success = get_missing_response(rsp, index);
        assert(success);
        missing_responses[index].base_type = btl::RSP;
        missing_responses[index].data = rsp.data;
    endfunction

    virtual function void complete_missing_rsp(Transaction rsp);
        int index;
        bit success = get_missing_response(rsp, index);
        assert(success);
        missing_responses.delete(index);
    endfunction

    ////////////////////////////////////////////////////////////////////////////
    // sub response methods
    ////////////////////////////////////////////////////////////////////////////

    // Outputs the index of the missing response that is missing the
    // passed in sub response and returns 1.  If there is no missing
    // response missing the passed in sub response, returns 0.
    virtual function bit get_missing_sub_rsp(Transaction sub_rsp,
                                             output int unsigned index);
        int unsigned results[$];
        results = missing_responses.find_index(rsp)
            with (rsp.is_missing_response(sub_rsp) == 1);
        if(results.size() == 0) begin
            return 0;
        end
        assert(results.size() <= 1);
        index = results[0];
        return 1;
    endfunction

    // Updates the missing sub response for the missing response at
    // index from INCOMPLETE_RSP to RSP, copying the data from the
    // passed in sub response to the missing sub response.  Get index
    // by calling get_missing_sub_rsp.
    virtual function void update_missing_sub_rsp(int unsigned index,
                                                 Transaction sub_rsp);
        assert(index < missing_responses.size());
        missing_responses[index].update_missing_rsp(sub_rsp);
    endfunction

    // Returns 1 if there are any missing sub responses for the
    // missing response at the given index.
    virtual function bit is_missing_sub_rsps(int unsigned index);
        foreach(missing_responses[index].missing_responses[i]) begin
            if(missing_responses[index].missing_responses[i].base_type
                == btl::INCOMPLETE_RSP) begin
                    return 1;
                end
        end
        return 0;
    endfunction

    // Copies data from all missing sub responses to the missing
    // response at index.
    function void sub_rsps_complete(int unsigned index);
        missing_responses[index].rsp_complete();
    endfunction

    function void end_of_test();
        assert(missing_responses.size() == 0);
    endfunction
endclass : ResponseTracker
