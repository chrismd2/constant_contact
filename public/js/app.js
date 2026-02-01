// Theme toggle functionality
(function() {
  const themeToggle = document.getElementById('theme-toggle');
  if (!themeToggle) return;

  // Check for saved theme preference or default to light mode
  const currentTheme = localStorage.getItem('theme') || 'light';
  if (currentTheme === 'dark') {
    document.documentElement.classList.add('dark');
  }

  themeToggle.addEventListener('click', function() {
    const isDark = document.documentElement.classList.toggle('dark');
    localStorage.setItem('theme', isDark ? 'dark' : 'light');
  });
})();

// API base URL
const API_BASE = '';

// Helper function to make API calls
async function apiCall(endpoint, options = {}) {
  const defaultOptions = {
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  };

  const response = await fetch(`${API_BASE}${endpoint}`, {
    ...defaultOptions,
    ...options,
    headers: {
      ...defaultOptions.headers,
      ...options.headers,
    },
  });

  // Check if response is actually JSON before parsing
  const contentType = response.headers.get('content-type');
  if (!contentType || !contentType.includes('application/json')) {
    const text = await response.text();
    throw new Error(`Expected JSON but got ${contentType}. Response: ${text.substring(0, 100)}`);
  }

  const data = await response.json();
  
  if (!response.ok) {
    // Handle different error response formats
    let errorMessage = `API error: ${response.status}`;
    if (Array.isArray(data) && data.length > 0) {
      // Constant Contact returns errors as an array
      errorMessage = data.map(err => err.error_message || err.error_key || JSON.stringify(err)).join(', ');
    } else if (data.error) {
      errorMessage = data.error.message || data.error.error_message || JSON.stringify(data.error);
    } else if (data.error_message) {
      errorMessage = data.error_message;
    }
    throw new Error(errorMessage);
  }

  return data;
}

// Format date helper
function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

// Format phone number helper
function formatPhone(phone) {
  if (!phone) return 'N/A';
  // Simple formatting - can be enhanced
  return phone;
}
