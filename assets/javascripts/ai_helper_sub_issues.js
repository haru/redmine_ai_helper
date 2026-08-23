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

// --- extracted from issues/subissues/_index.html.erb ---

/**
 * Generate sub-issue drafts via the AI helper for the given issue.
 * Exposed on `window` because the "generate draft" button's inline
 * `onclick` calls it directly.
 * @param {number} _issueId - unused; the endpoint URL is read from the
 *   wrapper's data-config instead (baked in server-side per issue).
 */
function aiHelperGenerateSubIssues(_issueId) {
  const wrapper = document.getElementById('ai-helper-subissues-index');
  const config = wrapper ? JSON.parse(wrapper.dataset.config || '{}') : {};
  const container = document.getElementById('ai-helper-generated-subissues');
  container.innerHTML = '<div class="ai-helper-loader"></div>';

  fetch(config.generateUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
    },
    body: JSON.stringify({
      instructions: document.getElementById('ai_helper_subissues_instructions').value
    })
  })
    .then(function(response) { return response.text(); })
    .then(function(html) {
      container.innerHTML = html;
    })
    .catch(function(error) {
      console.error('Error generating sub issues:', error);
      container.innerHTML = '<p>Error generating sub issues. Please try again later.</p>';
    });
}
window.aiHelperGenerateSubIssues = aiHelperGenerateSubIssues;

// --- extracted from issues/subissues/_description_bottom.html.erb ---

/**
 * Toggle visibility of the sub-issue generator area.
 * Exposed on `window` because the "generate sub-issues" link's inline
 * `onclick` calls it directly.
 */
function showSubissuerGenerator() {
  const generatorArea = document.getElementById('ai-helper-subissuer-generator-area');
  if (generatorArea) {
    generatorArea.style.display = generatorArea.style.display === 'none' ? 'block' : 'none';
  }
}
window.showSubissuerGenerator = showSubissuerGenerator;

document.addEventListener('DOMContentLoaded', function() {
  // Add span#ai-helper-subissuer-generator-menu as the first child of div#issue_tree > div.contextual
  const contextualDiv = document.querySelector('#issue_tree > div.contextual');
  if (contextualDiv) {
    const menuSpan = document.getElementById('ai-helper-subissuer-generator-menu');
    if (menuSpan) {
      // Insert the menuSpan as the first child for i18n support
      contextualDiv.insertBefore(menuSpan, contextualDiv.firstChild);
    }
  }

  const issueTreeDiv = document.getElementById('issue_tree');
  if (issueTreeDiv) {
    const generatorArea = document.getElementById('ai-helper-subissuer-generator-area');
    if (generatorArea) {
      issueTreeDiv.appendChild(generatorArea);
      generatorArea.style.display = 'none';
    }
  }
});
