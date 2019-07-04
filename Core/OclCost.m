% Copyright 2019 Jonas Koenemann, Moritz Diehl, University of Freiburg
% Redistribution is permitted under the 3-Clause BSD License terms. Please
% ensure the above copyright notice is visible in any derived work.
%
classdef OclCost < handle
  properties
    value
  end
  
  methods
    
    function self = OclCost()
      self.value = 0;
    end
    
    function add(self,val)
      % add(self,val)
      self.value = self.value + Variable.getValueAsColumn(val);
    end
  end
end
