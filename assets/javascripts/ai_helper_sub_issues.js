(function() {
  'use strict';
  
  let initialized = false;
  
  // Load assignees for a specific tracker
  function loadAssignees(trackerSelect) {
    const trackerId = trackerSelect.value;
    const projectId = trackerSelect.dataset.projectId;
    const rowIndex = trackerSelect.dataset.rowIndex;
    
    if (!trackerId || !projectId || !rowIndex) return;
    
    const assigneeSelect = document.getElementById('sub_issues_assigned_to_id_' + rowIndex);
    if (!assigneeSelect) return;
    
    const currentValue = assigneeSelect.value;
    const url = '/projects/' + projectId + '/ai_helper/assignable_users?tracker_id=' + trackerId;
    
    fetch(url)
      .then(function(response) {
        if (!response.ok) throw new Error('HTTP ' + response.status);
        return response.json();
      })
      .then(function(users) {
        assigneeSelect.innerHTML = '<option value=""></option>';
        users.forEach(function(user) {
          const option = document.createElement('option');
          option.value = user.id;
          option.textContent = user.name;
          assigneeSelect.appendChild(option);
        });
        
        if (currentValue) {
          assigneeSelect.value = currentValue;
        }
      })
      .catch(function(error) {
        console.error('Failed to load assignable users:', error);
      });
  }
  
  // Initialize all tracker selects
  function initializeAllTrackers() {
    if (initialized) return;
    
    const trackerSelects = document.querySelectorAll('.sub-issue-tracker-select');
    
    if (trackerSelects.length > 0) {
      initialized = true;
      
      trackerSelects.forEach(function(select) {
        if (select.value) {
          loadAssignees(select);
        }
      });
    }
  }
  
  // Listen for tracker changes
  document.addEventListener('change', function(e) {
    if (e.target.matches('.sub-issue-tracker-select')) {
      loadAssignees(e.target);
    }
  });
  
  // Setup MutationObserver to detect when sub-issues are loaded
  function setupObserver() {
    let mainContent = document.querySelector('#content');

    if (!mainContent) {
      mainContent = document.body;
    }
    
    if (!mainContent) return;
    
    const observer = new MutationObserver(function(mutations) {
      mutations.forEach(function(mutation) {
        if (mutation.addedNodes.length > 0) {
          let found = false;
          mutation.addedNodes.forEach(function(node) {
            if (node.nodeType === 1) {
              if (node.querySelector && node.querySelector('.sub-issue-tracker-select')) {
                found = true;
              }
            }
          });
          
          if (found) {
            initializeAllTrackers();
            observer.disconnect();
          }
        }
      });
    });
    
    observer.observe(mainContent, {
      childList: true,
      subtree: true
    });
  }
  
  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      setupObserver();
      setTimeout(initializeAllTrackers, 100);
    });
  } else {
    setupObserver();
    setTimeout(initializeAllTrackers, 100);
  }
})();
