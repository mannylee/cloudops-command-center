import {
  BreadcrumbGroup,
  Button,
  Container,
  Header,
  SpaceBetween,
  Box,
  ColumnLayout,
  Textarea,
  ContentLayout,
  Modal,
  FormField,
  Input,
} from "@cloudscape-design/components";
import BaseAppLayout from "../../../components/base-app-layout";
import { useOnFollow } from "../../../common/hooks/use-on-follow";
import { APP_NAME } from "../../../common/constants";
import { useEffect, useState } from "react";
import { ApiClient } from "../../../common/api-client/api-client";
import { OrgHealthFilter } from "../../../common/types";
import { useOrgHealth } from "../../../context/org-health-context";

export default function OrgHealthFilterPage() {
  const onFollow = useOnFollow();
  const { filters, setFilters, selectedFilter, setSelectedFilter } = useOrgHealth();
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [filterToDelete, setFilterToDelete] = useState<OrgHealthFilter | null>(null);
  const [filterToEdit, setFilterToEdit] = useState<OrgHealthFilter | null>(null);

  useEffect(() => {
    // Only fetch if filters are not already loaded in context
    if (filters.length === 0) {
      fetchData();
    } else {
      setLoading(false);
    }
  }, [filters.length]);

  async function fetchData() {
    try {
      setLoading(true);
      const apiClient = new ApiClient();
      const filtersData = await apiClient.orgHealth.getOrgHealthFilter();
      setFilters(filtersData);
    } catch (error) {
      console.error("Error fetching filters:", error);
    } finally {
      setLoading(false);
    }
  }

  const handleCreateFilter = async (filter: { filterName: string; description: string; accountIds: string[] }) => {
    try {
      const apiClient = new ApiClient();
      await apiClient.orgHealth.createOrgHealthFilter({
        filterName: filter.filterName,
        description: filter.description,
        accountIds: filter.accountIds,
        filterId: "",
      });
      await fetchData();
      setShowCreateModal(false);
    } catch (error) {
      console.error("Error creating filter:", error);
    }
  };

  const handleUpdateFilter = async (filter: OrgHealthFilter) => {
    try {
      const apiClient = new ApiClient();
      await apiClient.orgHealth.updateOrgHealthFilter(filter);
      await fetchData();
      setShowEditModal(false);
      setFilterToEdit(null);
    } catch (error) {
      console.error("Error updating filter:", error);
    }
  };

  const handleDeleteFilter = async () => {
    if (!filterToDelete) return;

    try {
      const apiClient = new ApiClient();
      await apiClient.orgHealth.deleteOrgHealthFilter(filterToDelete.filterId);
      await fetchData();
      setShowDeleteModal(false);
      setFilterToDelete(null);
    } catch (error) {
      console.error("Error deleting filter:", error);
    }
  };

  const confirmDelete = (filter: OrgHealthFilter) => {
    setFilterToDelete(filter);
    setShowDeleteModal(true);
  };

  const openEditModal = (filter: OrgHealthFilter) => {
    setFilterToEdit(filter);
    setShowEditModal(true);
  };

  return (
    <BaseAppLayout
      breadcrumbs={
        <BreadcrumbGroup
          onFollow={onFollow}
          items={[
            {
              text: APP_NAME,
              href: "/",
            },
            {
              text: "AWS Health Dashboard",
              href: "/",
            },
            {
              text: "Filter",
              href: "#",
            },
          ]}
        />
      }
      content={
        <ContentLayout
          header={
            <Header
              variant="h1"
              actions={
                <Button variant="primary" iconName="add-plus" onClick={() => setShowCreateModal(true)}>
                  Create new filter
                </Button>
              }
            >
              Health Dashboard Filters
            </Header>
          }
        >
          <SpaceBetween size="l">
            {loading ? (
              <Box textAlign="center" padding="l">
                Loading filters...
              </Box>
            ) : filters.length === 0 ? (
              <Box textAlign="center" padding="l">
                No filters available
              </Box>
            ) : (
              <ColumnLayout columns={1} variant="text-grid">
                {filters.map((filter, index) => (
                  <Container
                    key={index}
                    header={
                      <Header
                        variant="h2"
                        description={filter.description}
                        actions={
                          <SpaceBetween direction="horizontal" size="xs">
                            <Button 
                              variant="primary" 
                              onClick={() => setSelectedFilter(filter)}
                              disabled={selectedFilter?.filterId === filter.filterId}
                            >
                              {selectedFilter?.filterId === filter.filterId ? "Applied" : "Apply"}
                            </Button>
                            <Button onClick={() => openEditModal(filter)}>Edit</Button>
                            <Button onClick={() => confirmDelete(filter)}>Delete</Button>
                          </SpaceBetween>
                        }
                      >
                        {filter.filterName}
                      </Header>
                    }
                  >
                    <Textarea value={filter.accountIds?.join("\n") || ""} readOnly rows={3} />
                  </Container>
                ))}
              </ColumnLayout>
            )}
            <CreateFilterModal
              visible={showCreateModal}
              onDismiss={() => setShowCreateModal(false)}
              onCreate={handleCreateFilter}
            />
            <EditFilterModal
              visible={showEditModal}
              onDismiss={() => {
                setShowEditModal(false);
                setFilterToEdit(null);
              }}
              onUpdate={handleUpdateFilter}
              filter={filterToEdit}
            />
            <Modal
              visible={showDeleteModal}
              onDismiss={() => {
                setShowDeleteModal(false);
                setFilterToDelete(null);
              }}
              header="Confirm Delete"
              footer={
                <Box float="right">
                  <SpaceBetween direction="horizontal" size="xs">
                    <Button
                      variant="link"
                      onClick={() => {
                        setShowDeleteModal(false);
                        setFilterToDelete(null);
                      }}
                    >
                      Cancel
                    </Button>
                    <Button variant="primary" onClick={handleDeleteFilter}>
                      Delete
                    </Button>
                  </SpaceBetween>
                </Box>
              }
            >
              <Box variant="span">
                Are you sure you want to delete the filter <b>{filterToDelete?.filterName}</b>? This action cannot be
                undone.
              </Box>
            </Modal>
          </SpaceBetween>
        </ContentLayout>
      }
    />
  );
}

function CreateFilterModal({
  visible,
  onDismiss,
  onCreate,
}: {
  visible: boolean;
  onDismiss: () => void;
  onCreate: (filter: { filterName: string; description: string; accountIds: string[] }) => void;
}) {
  const [filterName, setFilterName] = useState("");
  const [description, setDescription] = useState("");
  const [accountIds, setAccountIds] = useState("");

  const handleCreate = () => {
    onCreate({
      filterName,
      description,
      accountIds: accountIds.split("\n").filter((id) => id.trim() !== ""),
    });
    setFilterName("");
    setDescription("");
    setAccountIds("");
  };

  return (
    <Modal
      visible={visible}
      onDismiss={onDismiss}
      header="Create New Filter"
      footer={
        <Box float="right">
          <SpaceBetween direction="horizontal" size="xs">
            <Button variant="link" onClick={onDismiss}>
              Cancel
            </Button>
            <Button variant="primary" onClick={handleCreate}>
              Create
            </Button>
          </SpaceBetween>
        </Box>
      }
    >
      <SpaceBetween size="l">
        <FormField label="Filter Name" description="Enter a name for this filter">
          <Input value={filterName} onChange={({ detail }) => setFilterName(detail.value)} />
        </FormField>
        <FormField label="Description" description="Enter a description for this filter">
          <Input value={description} onChange={({ detail }) => setDescription(detail.value)} />
        </FormField>
        <FormField label="Account IDs" description="Enter AWS account IDs, one per line">
          <Textarea value={accountIds} onChange={({ detail }) => setAccountIds(detail.value)} rows={5} />
        </FormField>
      </SpaceBetween>
    </Modal>
  );
}

function EditFilterModal({
  visible,
  onDismiss,
  onUpdate,
  filter,
}: {
  visible: boolean;
  onDismiss: () => void;
  onUpdate: (filter: OrgHealthFilter) => void;
  filter: OrgHealthFilter | null;
}) {
  const [filterName, setFilterName] = useState("");
  const [description, setDescription] = useState("");
  const [accountIds, setAccountIds] = useState("");

  useEffect(() => {
    if (filter) {
      setFilterName(filter.filterName);
      setDescription(filter.description);
      setAccountIds(filter.accountIds?.join("\n") || "");
    }
  }, [filter]);

  const handleUpdate = () => {
    if (!filter) return;

    onUpdate({
      ...filter,
      filterName,
      description,
      accountIds: accountIds.split("\n").filter((id) => id.trim() !== ""),
    });
  };

  return (
    <Modal
      visible={visible}
      onDismiss={onDismiss}
      header="Edit Filter"
      footer={
        <Box float="right">
          <SpaceBetween direction="horizontal" size="xs">
            <Button variant="link" onClick={onDismiss}>
              Cancel
            </Button>
            <Button variant="primary" onClick={handleUpdate}>
              Save
            </Button>
          </SpaceBetween>
        </Box>
      }
    >
      <SpaceBetween size="l">
        <FormField label="Filter Name" description="Enter a name for this filter">
          <Input value={filterName} onChange={({ detail }) => setFilterName(detail.value)} />
        </FormField>
        <FormField label="Description" description="Enter a description for this filter">
          <Input value={description} onChange={({ detail }) => setDescription(detail.value)} />
        </FormField>
        <FormField label="Account IDs" description="Enter AWS account IDs, one per line">
          <Textarea value={accountIds} onChange={({ detail }) => setAccountIds(detail.value)} rows={5} />
        </FormField>
      </SpaceBetween>
    </Modal>
  );
}
