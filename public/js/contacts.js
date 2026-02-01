// Contacts page functionality
(function() {
  const loadingEl = document.getElementById('loading');
  const errorEl = document.getElementById('error');
  const errorMessageEl = document.getElementById('error-message');
  const contactsContainer = document.getElementById('contacts-container');
  const emptyState = document.getElementById('empty-state');
  const contactCount = document.getElementById('contact-count');
  const contactModal = document.getElementById('contact-modal');
  const modalContent = document.getElementById('modal-content');
  const modalTitle = document.getElementById('modal-title');
  const modalClose = document.getElementById('modal-close');
  const modalCloseBtn = document.getElementById('modal-close-btn');
  const modalBackdrop = document.getElementById('modal-backdrop');

  // Load contacts on page load
  document.addEventListener('DOMContentLoaded', loadContacts);

  // Modal close handlers
  if (modalClose) {
    modalClose.addEventListener('click', closeModal);
  }
  if (modalCloseBtn) {
    modalCloseBtn.addEventListener('click', closeModal);
  }
  if (modalBackdrop) {
    modalBackdrop.addEventListener('click', closeModal);
  }

  // Close modal on Escape key
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && contactModal && !contactModal.classList.contains('hidden')) {
      closeModal();
    }
  });

  async function loadContacts() {
    try {
      showLoading();
      const data = await apiCall('/contacts?limit=100');
      hideLoading();

      // Handle empty response or missing contacts array
      if (!data || (!data.contacts && !Array.isArray(data))) {
        showEmptyState();
        return;
      }

      // Handle both {contacts: [...]} and [...] response formats
      const contacts = data.contacts || (Array.isArray(data) ? data : []);
      
      if (contacts.length === 0) {
        showEmptyState();
        return;
      }

      displayContacts(contacts);
      updateContactCount(contacts.length, data.meta?.pagination?.total_count);
    } catch (error) {
      hideLoading();
      showError(error.message);
      console.error('Error loading contacts:', error);
    }
  }

  function showLoading() {
    if (loadingEl) loadingEl.classList.remove('hidden');
    if (errorEl) errorEl.classList.add('hidden');
    if (contactsContainer) contactsContainer.classList.add('hidden');
    if (emptyState) emptyState.classList.add('hidden');
  }

  function hideLoading() {
    if (loadingEl) loadingEl.classList.add('hidden');
  }

  function showError(message) {
    if (errorEl) {
      errorEl.classList.remove('hidden');
      if (errorMessageEl) {
        errorMessageEl.textContent = message;
      }
    }
    if (contactsContainer) contactsContainer.classList.add('hidden');
    if (emptyState) emptyState.classList.add('hidden');
  }

  function showEmptyState() {
    if (emptyState) emptyState.classList.remove('hidden');
    if (contactsContainer) contactsContainer.classList.add('hidden');
    if (errorEl) errorEl.classList.add('hidden');
  }

  function displayContacts(contacts) {
    if (!contactsContainer) return;

    contactsContainer.classList.remove('hidden');
    contactsContainer.innerHTML = '';

    contacts.forEach(contact => {
      const card = createContactCard(contact);
      contactsContainer.appendChild(card);
    });
  }

  function createContactCard(contact) {
    const card = document.createElement('div');
    card.className = 'bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700 p-6 hover:shadow-md transition-shadow cursor-pointer';
    
    const email = contact.email_address?.address || 'No email';
    const firstName = contact.first_name || '';
    const lastName = contact.last_name || '';
    const fullName = `${firstName} ${lastName}`.trim() || email;
    const company = contact.company_name || '';
    const status = contact.status || 'unknown';

    card.innerHTML = `
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white">${escapeHtml(fullName)}</h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">${escapeHtml(email)}</p>
          ${company ? `<p class="mt-1 text-sm text-gray-500 dark:text-gray-400">${escapeHtml(company)}</p>` : ''}
        </div>
        <span class="ml-4 inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
          status === 'ACTIVE' ? 'bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400' :
          status === 'UNSUBSCRIBED' ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400' :
          'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300'
        }">
          ${status}
        </span>
      </div>
    `;

    card.addEventListener('click', () => showContactDetails(contact.contact_id));

    return card;
  }

  async function showContactDetails(contactId) {
    try {
      const contact = await apiCall(`/contacts/${contactId}`);
      displayContactModal(contact);
    } catch (error) {
      alert('Error loading contact details: ' + error.message);
      console.error('Error loading contact:', error);
    }
  }

  function displayContactModal(contact) {
    if (!contactModal || !modalContent) return;

    const email = contact.email_address || {};
    const address = contact.street_address || {};
    const phone = contact.phone_number || {};
    
    modalContent.innerHTML = `
      <div class="space-y-4">
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Email</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${escapeHtml(email.address || 'N/A')}</p>
          ${email.permission_to_send ? `<p class="mt-1 text-sm text-gray-500 dark:text-gray-400">Permission: ${escapeHtml(email.permission_to_send)}</p>` : ''}
        </div>
        
        ${contact.first_name || contact.last_name ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Name</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${escapeHtml(`${contact.first_name || ''} ${contact.last_name || ''}`.trim() || 'N/A')}</p>
        </div>
        ` : ''}
        
        ${phone.phone_number ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Phone</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${escapeHtml(phone.phone_number)}</p>
        </div>
        ` : ''}
        
        ${contact.company_name ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Company</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${escapeHtml(contact.company_name)}</p>
        </div>
        ` : ''}
        
        ${contact.job_title ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Job Title</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${escapeHtml(contact.job_title)}</p>
        </div>
        ` : ''}
        
        ${address.street || address.city || address.state_code || address.postal_code ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Address</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">
            ${escapeHtml([
              address.street,
              address.city,
              address.state_code,
              address.postal_code,
              address.country_code
            ].filter(Boolean).join(', ') || 'N/A')}
          </p>
        </div>
        ` : ''}
        
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Status</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${escapeHtml(contact.status || 'N/A')}</p>
        </div>
        
        ${contact.created_at ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Created</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${formatDate(contact.created_at)}</p>
        </div>
        ` : ''}
        
        ${contact.updated_at ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Updated</h4>
          <p class="mt-1 text-base text-gray-900 dark:text-white">${formatDate(contact.updated_at)}</p>
        </div>
        ` : ''}
        
        ${contact.contact_id ? `
        <div>
          <h4 class="text-sm font-semibold text-gray-500 dark:text-gray-400">Contact ID</h4>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400 font-mono">${escapeHtml(contact.contact_id)}</p>
        </div>
        ` : ''}
      </div>
    `;

    contactModal.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
  }

  function closeModal() {
    if (contactModal) {
      contactModal.classList.add('hidden');
      document.body.style.overflow = '';
    }
  }

  function updateContactCount(displayed, total) {
    if (!contactCount) return;
    if (total && total > displayed) {
      contactCount.textContent = `Showing ${displayed} of ${total} contacts`;
    } else {
      contactCount.textContent = `${displayed} contact${displayed !== 1 ? 's' : ''}`;
    }
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
})();
