/**
 * @file
 * @copyright 2021
 * @author Original BenLubar (https://github.com/BenLubar)
 * @author Changes Mordent (https://github.com/mordent-goonstation)
 * @license ISC
 */

import { useBackend, useSharedState } from '../../../backend';
import { Box, Button, Modal, Section, Stack } from '../../../components';

export const CombineGenesModal = (_props, context) => {
  const { data, act } = useBackend(context);
  const [isCombining, setIsCombining] = useSharedState(context, 'iscombining', false);
  const { savedMutations, combining = [] } = data;
  return (
    <Modal full width={20}>
      <Section title="Select">
        <Stack vertical>
          {savedMutations.map((g) => (
            <Stack.Item key={g.ref}>
              <Button.Checkbox
                checked={combining.indexOf(g.ref) >= 0}
                onClick={() => act('togglecombine', { ref: g.ref })}>
                {g.name}
              </Button.Checkbox>
            </Stack.Item>
          ))}
        </Stack>
      </Section>
      <Box textAlign="center">
        <Button color="bad" icon="times" onClick={() => setIsCombining(false)}>
          Cancel
        </Button>
        <Button
          icon="sitemap"
          disabled={!combining.length}
          onClick={() => {
            act('combinegenes');
            setIsCombining(false);
          }}>
          Combine
        </Button>
      </Box>
    </Modal>
  );
};
