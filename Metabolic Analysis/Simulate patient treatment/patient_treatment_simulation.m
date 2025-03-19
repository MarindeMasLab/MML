%%%% "Treat" patients and characterize
% Initial parameters and tools
initCobraToolbox;
load('working_environment_treated_patients.mat');

% Initial parameters
ini_model = 1;
end_model = length(patient_models_to_treat);

% Routine
for m = ini_model:length(patient_models_to_treat)
    %%% 1. Load the mth model
    mth_model_name = patient_models_to_treat(m);
    mth_model = strcat(folder,mth_model_name);
    mth_model = load(mth_model{1});
    mth_model = mth_model.sampleMetaOutC;
    % 2. Change boundaries of exchange reactions
    % assign the less restrictive boundary between patients boundaries and
    % the mean max value in target/reference group
    for e = 1:length(ex_rxn_index)
        % lb %
        patient_lb = mth_model.lb(ex_rxn_index(e));
        group_a_lb = mean_min_2(e);
        original_lb = patient_lb; % Modified to not account for the 
        % boundaries in the original model. To take into account replace 
        % by: model.lb(ex_rxn_index(e));    
        mth_model.lb(ex_rxn_index(e)) = min([original_lb,patient_lb,group_a_lb]);     
        % ub %
        patient_ub = mth_model.ub(ex_rxn_index(e));
        group_a_ub = mean_max_2(e);
        original_ub = patient_ub; % Modified to not account for the 
        % boundaries in the original model. To take into account replace 
        % by: model.ub(ex_rxn_index(e));  
        mth_model.ub(ex_rxn_index(e)) = max([original_ub,patient_ub,group_a_ub]);
    end 
    % 3. Impose constraints on the relevant reactions
    for r = 1:length(relevant_reactions_shape_subset)
        mth_model.lb(relevant_reactions_shape_subset(r)) = mean_min(r)*0.1;
        mth_model.ub(relevant_reactions_shape_subset(r)) = mean_max(r);
    end
    % 4. Check feasibility of the model and relax constraints if necessary
    fba = optimizeCbModel(mth_model);
    if fba.f <= 0
        fprintf('Model is infeasible after initial boundary changes.\n');        
        % 4.1 Relax boundaries iteratively
        relaxation_step = 1e-6; % Adjust the relaxation step as needed
        max_relaxation = 1; % Set a reasonable limit for relaxation
        relaxed_reactions = false(length(relevant_reactions_shape_subset), 1);        
        while fba.f <= 0
            for fba = 1:length(relevant_reactions_shape_subset)
                if ~relaxed_reactions(fba)
                    % Relax lower bound
                    mth_model.lb(relevant_reactions_shape_subset(fba)) = mth_model.lb(relevant_reactions_shape_subset(fba)) - relaxation_step;
                    % Relax upper bound
                    mth_model.ub(relevant_reactions_shape_subset(fba)) = mth_model.ub(relevant_reactions_shape_subset(fba)) + relaxation_step;                    
                    % Check feasibility
                    fba = optimizeCbModel(mth_model);
                    if fba.f > 0
                        fprintf('Model became feasible after relaxing reaction %d\n', relevant_reactions_shape_subset(fba));
                        relaxed_reactions(fba) = true;
                        break;
                    else
                        % Revert changes if still infeasible
                        mth_model.lb(relevant_reactions_shape_subset(fba)) = mth_model.lb(relevant_reactions_shape_subset(fba)) + relaxation_step;
                        mth_model.ub(relevant_reactions_shape_subset(fba)) = mth_model.ub(relevant_reactions_shape_subset(fba)) - relaxation_step;
                    end
                end
            end            
            % 4.2 Check if all reactions have been relaxed
            if all(relaxed_reactions)
                fprintf('All reactions have been relaxed to the maximum limit.\n');
                break;
            end            
            % 4.3 Increase relaxation step if necessary
            relaxation_step = relaxation_step * 2;
            if relaxation_step > max_relaxation
                fprintf('Relaxation step exceeded maximum limit.\n');
                break;
            end
        end
        % Restore original bounds if infeasible
        if fba.f <= 0
            fprintf('Model is still infeasible after relaxation. Restoring original bounds.\n');
            for r_idx = 1:length(relevant_reactions_shape_subset)
                mth_model.lb(relevant_reactions_shape_subset(r_idx)) = mean_min(r_idx) * 0.1;
                mth_model.ub(relevant_reactions_shape_subset(r_idx)) = mean_max(r_idx);
            end
        end        
    end
    % 5. Sampling      
    mth_model = rmfield(mth_model, {'points', 'steps', 'warmupPts', 'internal', 'A'}); % Remove 
    % All the sampling element from the model before sampling the "treated" patient 
    fba = optimizeCbModel(mth_model);
    mth_model.lb(find(mth_model.c)) = 0.5*fba.f; % Ensure biomass production
    [model_treated, ~] = gpSampler(mth_model, length(mth_model.rxns), [], 8*3600,length(mth_model.rxns)*2);    
    %[model_treated, ~] = gpSampler(mth_model, 500, [], 2,10); %This is just
    %for testing purposes and must be commented
    % 6. Save treated model
    output_model_name = strrep(mth_model_name{1}, '.mat', '_treated'); % Define an unique model name
    save(output_model_name, 'model_treated');
end
